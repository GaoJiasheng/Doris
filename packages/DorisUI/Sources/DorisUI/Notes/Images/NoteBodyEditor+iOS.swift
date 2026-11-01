#if os(iOS)
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import DorisCore

/// The note body editor on iOS: plain text, with images shown in place.
///
/// Grows with its content rather than scrolling, so it sits inside the
/// screen's own scroll view. Paste an image and it lands on its own line
/// at the cursor; tap it for sizes, full size and delete. The body stays
/// Markdown (see `NoteBodyTextBridge`).
public struct NoteBodyEditor: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var ctx
    var inset: CGSize
    var minHeight: CGFloat
    var readOnly: Bool

    /// `minHeight`: the text view itself is at least this tall, so a tap
    /// anywhere in that area starts editing. `readOnly`: the reading view —
    /// same text, styles and images, links tappable, no keyboard.
    public init(note: Note, inset: CGSize = .zero, minHeight: CGFloat = 0, readOnly: Bool = false) {
        self.note = note
        self.inset = inset
        self.minHeight = minHeight
        self.readOnly = readOnly
    }

    public var body: some View {
        NoteBodyTextViewIOS(note: note, modelContext: ctx, inset: inset, minHeight: minHeight,
                            readOnly: readOnly)
    }
}

/// Image bytes on a pasteboard, raw where possible so a photo isn't
/// re-encoded twice.
enum NoteImagePasteboard {
    static func imageDatas(from pb: UIPasteboard) -> [Data] {
        var out: [Data] = []
        for item in pb.items {
            let key = item.keys.first { UTType($0)?.conforms(to: .image) == true }
            guard let key, let value = item[key] else { continue }
            if let data = value as? Data { out.append(data) }
            else if let image = value as? UIImage, let data = image.pngData() { out.append(data) }
        }
        return out
    }

    /// What a paste should insert as images, if anything: the images,
    /// unless the pasteboard's text is real text (copying part of a page
    /// carries text plus pictures and means the text) rather than a link
    /// riding along with a copied image.
    static func pastedImages(from pb: UIPasteboard) -> [Data] {
        guard pb.hasImages else { return [] }
        if pb.hasStrings, let text = pb.string, NoteImagePasteRule.isProse(text) { return [] }
        return imageDatas(from: pb)
    }
}

final class NoteBodyUITextView: UITextView {
    var onImages: (([Data]) -> Void)?
    var onWidthChange: (() -> Void)?
    var onLayout: (() -> Void)?
    var markdownForRange: ((NSRange) -> String)?
    /// The plain look (font, colour) styles are put on top of.
    var baseAttributes: () -> [NSAttributedString.Key: Any] = { [:] }
    private var lastWidth: CGFloat = 0

    /// The body's own text form, with its marks, beside the plain text on
    /// the pasteboard — copying between notes keeps bold / underline /
    /// highlight, pasting elsewhere gets clean text.
    static let bodyType = "com.gavin.doris.body"

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        let images = NoteImagePasteboard.pastedImages(from: pb)
        if !images.isEmpty { onImages?(images); return }
        // Copied from a note: the text goes in as typed text (so undo and
        // the usual change handling work), then gets its styles back.
        if let data = pb.data(forPasteboardType: Self.bodyType),
           let body = String(data: data, encoding: .utf8),
           !body.contains(NoteImageMarkup.scheme),
           let range = selectedTextRange {
            let styled = NoteBodyTextBridge.attributedString(markdown: body, attributes: baseAttributes())
            let start = offset(from: beginningOfDocument, to: range.start)
            replace(range, withText: styled.string)
            styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length)) { attrs, r, _ in
                textStorage.setAttributes(attrs, range: NSRange(location: start + r.location, length: r.length))
            }
            delegate?.textViewDidChange?(self)
            return
        }
        super.paste(sender)
    }

    /// Copying puts the selection's text form (marks, image lines) on the
    /// pasteboard for notes, and plain text — or the image lines, so another
    /// note still finds the images — for everything else.
    override func copy(_ sender: Any?) {
        guard writeSelection() else { return super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        guard writeSelection() else { return super.cut(sender) }
        replace(selectedTextRange ?? UITextRange(), withText: "")
    }

    private func writeSelection() -> Bool {
        guard let md = markdownForRange?(selectedRange), !md.isEmpty else { return false }
        let plain = md.contains(NoteImageMarkup.scheme) ? md : NoteInlineMarkup.plain(md)
        UIPasteboard.general.items = [[
            Self.bodyType: Data(md.utf8),
            UTType.utf8PlainText.identifier: plain,
        ]]
        return true
    }

    // MARK: Bold / underline / highlight

    /// The style the next typed text takes. Set by a toolbar tap with
    /// nothing selected (UIKit's typing attributes don't keep our keys, and
    /// are rebuilt on every selection change); cleared once the caret moves.
    var pendingTypingStyle: NoteInlineMarkup.Style?

    /// The style typed text should have here: the one just switched on,
    /// else that of the character before the caret.
    var styleAtCaret: NoteInlineMarkup.Style {
        if let pendingTypingStyle { return pendingTypingStyle }
        let at = selectedRange.location
        guard at > 0, at <= textStorage.length else { return .init() }
        let ns = textStorage.string as NSString
        let prev = ns.character(at: at - 1)
        if prev == 0x0A || prev == 0xFFFC { return .init() }
        return NoteRichText.style(of: textStorage.attributes(at: at - 1, effectiveRange: nil))
    }

    func applyRichText(_ command: NoteRichText.Command) {
        guard markedTextRange == nil else { return }
        let range = selectedRange
        if range.length == 0 {
            // Nothing selected: what's typed next takes (or drops) the style.
            let next = NoteRichText.typingStyle(styleAtCaret, after: command)
            pendingTypingStyle = next
            typingAttributes = NoteRichText.attributes(next, base: baseAttributes())
            return
        }
        let before = textStorage.attributedSubstring(from: range)
        textStorage.beginEditing()
        NoteRichText.apply(command, to: textStorage, range: range, base: baseAttributes())
        textStorage.endEditing()
        registerUndo(restoring: before, at: range)
        selectedRange = range
        delegate?.textViewDidChange?(self)
    }

    /// Undo a style change by putting the old runs back (and redo the same way).
    private func registerUndo(restoring old: NSAttributedString, at range: NSRange) {
        undoManager?.registerUndo(withTarget: self) { tv in
            guard range.location + range.length <= tv.textStorage.length,
                  tv.textStorage.attributedSubstring(from: range).string == old.string else { return }
            let now = tv.textStorage.attributedSubstring(from: range)
            old.enumerateAttributes(in: NSRange(location: 0, length: old.length)) { attrs, r, _ in
                tv.textStorage.setAttributes(attrs, range: NSRange(location: range.location + r.location,
                                                                   length: r.length))
            }
            tv.registerUndo(restoring: now, at: range)
            tv.delegate?.textViewDidChange?(tv)
        }
        undoManager?.setActionName(L("Format", "格式"))
    }

    /// 格式 in the text menu, for a selection.
    var formatMenu: UIMenu {
        let highlight = UIMenu(title: L("Highlight", "高亮"), image: UIImage(systemName: "highlighter"),
                               children: NoteFormatBar.colours.map { h in
            UIAction(title: NoteFormatBar.name(h), image: NoteRichText.swatch(h)) {
                [weak self] _ in self?.applyRichText(.highlight(h))
            }
        } + [UIAction(title: L("Remove Highlight", "清除高亮"), image: UIImage(systemName: "eraser")) {
            [weak self] _ in self?.applyRichText(.highlight(nil))
        }])
        return UIMenu(title: L("Format", "格式"), image: UIImage(systemName: "textformat"), children: [
            UIAction(title: L("Bold", "加粗"), image: UIImage(systemName: "bold")) { [weak self] _ in
                self?.applyRichText(.bold)
            },
            UIAction(title: L("Underline", "下划线"), image: UIImage(systemName: "underline")) { [weak self] _ in
                self?.applyRichText(.underline)
            },
            highlight,
        ])
    }

    /// B · U · highlight above the keyboard, and a button to put it away.
    lazy var formatAccessory: UIToolbar = {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        func item(_ symbol: String, _ label: String, _ command: NoteRichText.Command) -> UIBarButtonItem {
            let b = UIBarButtonItem(image: UIImage(systemName: symbol),
                                    primaryAction: UIAction { [weak self] _ in self?.applyRichText(command) })
            b.accessibilityLabel = label
            return b
        }
        let highlight = UIBarButtonItem(
            image: UIImage(systemName: "highlighter"),
            primaryAction: UIAction { [weak self] _ in self?.applyRichText(.highlight(.yellow)) },
            menu: (formatMenu.children.last as? UIMenu))
        highlight.accessibilityLabel = L("Highlight Yellow", "黄色高亮")
        // The colours, under a name: 高亮 ⌄ opens them on a tap.
        var config = UIButton.Configuration.plain()
        config.title = L("Highlight", "高亮")
        config.image = UIImage(systemName: "chevron.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
        let colourButton = UIButton(configuration: config)
        colourButton.menu = formatMenu.children.last as? UIMenu
        colourButton.showsMenuAsPrimaryAction = true
        colourButton.accessibilityLabel = L("Highlight Colour", "高亮颜色")
        let colours = UIBarButtonItem(customView: colourButton)
        let done = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"),
                                   primaryAction: UIAction { [weak self] _ in self?.resignFirstResponder() })
        done.accessibilityLabel = L("Hide Keyboard", "收起键盘")
        bar.items = [item("bold", L("Bold", "加粗"), .bold),
                     item("underline", L("Underline", "下划线"), .underline),
                     highlight,
                     colours,
                     UIBarButtonItem(systemItem: .flexibleSpace),
                     done]
        bar.sizeToFit()
        return bar
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            onWidthChange?()
        }
        onLayout?()
    }
}

struct NoteBodyTextViewIOS: UIViewRepresentable {
    @Bindable var note: Note
    let modelContext: ModelContext
    var inset: CGSize
    var minHeight: CGFloat
    var readOnly = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> NoteBodyUITextView {
        // TextKit 1: mature, predictable attachment sizing.
        let tv = NoteBodyUITextView(usingTextLayoutManager: false)
        tv.isScrollEnabled = false            // grow; the screen scrolls
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: inset.height, left: inset.width,
                                             bottom: inset.height, right: inset.width)
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.smartQuotesType = .no              // keep Markdown literal
        tv.smartDashesType = .no
        tv.typingAttributes = context.coordinator.baseAttributes
        tv.delegate = context.coordinator
        if readOnly {
            tv.isEditable = false
            tv.dataDetectorTypes = [.link, .phoneNumber]
        } else {
            tv.inputAccessoryView = tv.formatAccessory
        }
        tv.setContentHuggingPriority(.required, for: .vertical)

        let c = context.coordinator
        c.textView = tv
        tv.onImages = { [weak c] datas in c?.insertImages(datas) }
        tv.baseAttributes = { [weak c] in c?.baseAttributes ?? [:] }
        tv.onWidthChange = { [weak c] in c?.layoutAttachments() }
        tv.onLayout = { [weak c] in c?.placeImageButtons() }
        tv.markdownForRange = { [weak c] range in c?.markdown(in: range) ?? "" }
        c.load(note.bodyMarkdown, noteID: note.id)
        c.observeInsertRequests()
        return tv
    }

    func updateUIView(_ tv: NoteBodyUITextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        // Reload only for a change that didn't come from this view, and
        // never while the input method is composing.
        if c.noteID != note.id || (note.bodyMarkdown != c.lastMarkdown && tv.markedTextRange == nil) {
            c.load(note.bodyMarkdown, noteID: note.id)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NoteBodyUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        context.coordinator.layoutAttachments(forWidth: width)
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minHeight, ceil(fit.height)))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteBodyTextViewIOS
        weak var textView: NoteBodyUITextView?
        var lastMarkdown = ""
        var noteID: UUID?
        private var laidOutWidth: CGFloat = 0
        private var retry: Timer?
        private var imageButtons: [UIButton] = []
        private var insertObserver: NSObjectProtocol?
        /// Where the caret was last put by the user; nil until then, so
        /// an image added from the toolbar before any editing goes at the end.
        private var userSelection: NSRange?

        init(_ parent: NoteBodyTextViewIOS) { self.parent = parent }

        deinit {
            if let insertObserver { NotificationCenter.default.removeObserver(insertObserver) }
        }

        var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label]
        }

        func load(_ markdown: String, noteID: UUID) {
            guard let tv = textView else { return }
            let selection = tv.selectedRange
            tv.textStorage.setAttributedString(NoteBodyTextBridge.attributedString(markdown: markdown,
                                                                                    attributes: baseAttributes))
            tv.typingAttributes = baseAttributes
            lastMarkdown = markdown
            if self.noteID == noteID {
                tv.selectedRange = NSRange(location: min(selection.location, tv.textStorage.length), length: 0)
            }
            self.noteID = noteID
            layoutAttachments()
        }

        /// "Insert image" from the screen's toolbar lands at the cursor.
        /// Synchronous (queue nil) so the sender sees `handled`.
        func observeInsertRequests() {
            insertObserver = NotificationCenter.default.addObserver(
                forName: .dorisInsertNoteImages, object: nil, queue: nil) { [weak self] n in
                MainActor.assumeIsolated {
                    guard let self, let request = n.object as? NoteImageInsertion.Request,
                          request.noteID == self.parent.note.id, !request.handled,
                          self.textView?.window != nil else { return }
                    request.handled = true
                    self.insertImages(request.datas)
                }
            }
        }

        // MARK: Layout

        func layoutAttachments(forWidth width: CGFloat? = nil) {
            guard let tv = textView else { return }
            let total = width ?? tv.bounds.width
            guard total > 0 else { return }
            let column = max(60, total - tv.textContainerInset.left - tv.textContainerInset.right
                             - tv.textContainer.lineFragmentPadding * 2)
            laidOutWidth = total
            var waiting = false
            let storage = tv.textStorage
            for (a, range) in NoteBodyTextBridge.attachments(in: storage) {
                if NoteBodyTextBridge.layout(a, width: column, context: parent.modelContext,
                                             scale: tv.traitCollection.displayScale) {
                    waiting = true
                }
                tv.layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                tv.layoutManager.invalidateDisplay(forCharacterRange: range)
            }
            tv.invalidateIntrinsicContentSize()
            scheduleRetry(waiting)
        }

        /// An image's line can sync before its bytes; look again every few
        /// seconds until they've all arrived.
        private func scheduleRetry(_ needed: Bool) {
            retry?.invalidate()
            retry = nil
            guard needed else { return }
            retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.layoutAttachments() }
            }
        }

        /// A transparent button over each image: a tap shows it full size,
        /// a long press opens the image menu. (Attachments in an editable
        /// text view don't get UIKit's own text-item interactions.)
        func placeImageButtons() {
            guard let tv = textView else { return }
            let found = NoteBodyTextBridge.attachments(in: tv.textStorage)
            while imageButtons.count < found.count {
                let b = UIButton(type: .custom)
                b.showsMenuAsPrimaryAction = false   // the menu is on long press
                b.accessibilityLabel = L("Image", "图片")
                tv.addSubview(b)
                imageButtons.append(b)
            }
            while imageButtons.count > found.count { imageButtons.removeLast().removeFromSuperview() }
            let lm = tv.layoutManager
            for ((a, range), button) in zip(found, imageButtons) {
                // An attachment is drawn standing on the baseline.
                let glyph = lm.glyphIndexForCharacter(at: range.location)
                let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let loc = lm.location(forGlyphAt: glyph)
                let rect = CGRect(x: tv.textContainerInset.left + line.minX + loc.x,
                                  y: tv.textContainerInset.top + line.minY + loc.y - a.bounds.height,
                                  width: a.bounds.width, height: a.bounds.height)
                if button.frame != rect { button.frame = rect }
                button.menu = menu(for: a)
                // Same identifier each time, so this replaces the last one.
                button.addAction(UIAction(identifier: .init("doris.image.view")) { [weak self, weak a] _ in
                    guard let a, !a.isPlaceholder else { return }
                    self?.viewFull(a.ref.id)
                }, for: .primaryActionTriggered)
            }
        }

        private func menu(for a: NoteImageTextAttachment) -> UIMenu {
            let sizes = NoteImageSize.allCases.map { size in
                UIAction(title: size.label, state: a.ref.size == size ? .on : .off) { [weak self, weak a] _ in
                    guard let a else { return }
                    self?.resize(a, to: size)
                }
            }
            let view = UIAction(title: L("View Full Size", "查看大图"),
                                image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
                                attributes: a.isPlaceholder ? .disabled : []) { [weak self, weak a] _ in
                guard let a else { return }
                self?.viewFull(a.ref.id)
            }
            let delete = UIAction(title: L("Delete Image", "删除图片"), image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { [weak self, weak a] _ in
                guard let a else { return }
                self?.delete(a)
            }
            // Reading: look, don't change.
            if parent.readOnly { return UIMenu(children: [view]) }
            return UIMenu(children: [UIMenu(options: .displayInline, children: sizes), view, delete])
        }

        func markdown(in range: NSRange) -> String {
            guard let storage = textView?.textStorage, range.length > 0 else { return "" }
            return NoteBodyTextBridge.markdown(from: storage.attributedSubstring(from: range))
        }

        // MARK: Editing

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // Never let typed text pick up an image's attachment attribute —
            // but keep its bold / underline / highlight.
            if let tv = self.textView {
                textView.typingAttributes = NoteRichText.attributes(tv.styleAtCaret, base: baseAttributes)
            }
            return true
        }

        /// A selection's text menu gets 格式 (bold, underline, highlight).
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let tv = self.textView else { return nil }
            return UIMenu(children: suggestedActions + [tv.formatMenu])
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.isFirstResponder { userSelection = textView.selectedRange }
            // Typing moves the caret too; from here the character before it
            // carries the style. A tap elsewhere drops a pending style.
            self.textView?.pendingTypingStyle = nil
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let tv = self.textView else { return }
            // Don't publish a half-composed input method buffer (pinyin,
            // kana); UIKit calls this again once it's committed.
            guard tv.markedTextRange == nil else { return }
            let storage = tv.textStorage
            if NoteBodyTextBridge.hasTextImageLine(storage) {
                // An image line pasted as text: show it as the image, keeping
                // the caret after what was pasted.
                let md = NoteBodyTextBridge.markdown(from: storage)
                let caret = min(tv.selectedRange.location, storage.length)
                let before = NoteBodyTextBridge.markdown(from: storage.attributedSubstring(from: NSRange(location: 0, length: caret)))
                load(md, noteID: noteID ?? parent.note.id)
                let newCaret = NoteBodyTextBridge.attributedString(markdown: before, attributes: [:]).length
                tv.selectedRange = NSRange(location: min(newCaret, storage.length), length: 0)
                commit(md)
                return
            }
            let fixes = NoteBodyTextBridge.lineBreakFixes(in: storage)
            if !fixes.isEmpty {
                let selection = tv.selectedRange
                for at in fixes { storage.insert(NSAttributedString(string: "\n", attributes: baseAttributes), at: at) }
                let shift = fixes.filter { $0 <= selection.location }.count
                tv.selectedRange = NSRange(location: selection.location + shift, length: 0)
            }
            commit(NoteBodyTextBridge.markdown(from: storage))
        }

        private func commit(_ md: String) {
            guard md != lastMarkdown else { return }
            lastMarkdown = md
            parent.note.bodyMarkdown = md
        }

        func insertImages(_ datas: [Data]) {
            guard let tv = textView else { return }
            let refs = datas.compactMap { NoteImageStore.add(imageData: $0, to: parent.note, in: parent.modelContext) }
            guard !refs.isEmpty else { return }
            let storage = tv.textStorage
            let target = tv.isFirstResponder ? tv.selectedRange
                : userSelection ?? NSRange(location: storage.length, length: 0)
            let at = min(target.location, storage.length)
            let ns = storage.string as NSString
            let insertion = NSMutableAttributedString()
            if at > 0, ns.character(at: at - 1) != 0x0A {
                insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            for (i, ref) in refs.enumerated() {
                if i > 0 { insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes)) }
                let a = NSMutableAttributedString(attachment: NoteImageTextAttachment(ref: ref))
                a.addAttributes(baseAttributes, range: NSRange(location: 0, length: a.length))
                insertion.append(a)
            }
            // Break after the image unless the line already ends there.
            let end = min(at + target.length, ns.length)
            if end >= ns.length || ns.character(at: end) != 0x0A {
                insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            storage.replaceCharacters(in: NSRange(location: at, length: end - at), with: insertion)
            tv.selectedRange = NSRange(location: at + insertion.length, length: 0)
            tv.typingAttributes = baseAttributes
            layoutAttachments()
            commit(NoteBodyTextBridge.markdown(from: storage))
        }

        private func range(of a: NoteImageTextAttachment) -> NSRange? {
            guard let tv = textView else { return nil }
            return NoteBodyTextBridge.attachments(in: tv.textStorage).first { $0.0 === a }?.1
        }

        private func resize(_ a: NoteImageTextAttachment, to size: NoteImageSize) {
            guard let tv = textView else { return }
            a.ref.size = size
            layoutAttachments()
            commit(NoteBodyTextBridge.markdown(from: tv.textStorage))
        }

        private func delete(_ a: NoteImageTextAttachment) {
            guard let tv = textView, let r = range(of: a) else { return }
            // Take the image's line break with it, so no blank line is left.
            let storage = tv.textStorage
            let ns = storage.string as NSString
            var cut = NSRange(location: r.location, length: 1)
            if r.location + 1 < ns.length, ns.character(at: r.location + 1) == 0x0A { cut.length = 2 }
            else if r.location > 0, ns.character(at: r.location - 1) == 0x0A { cut = NSRange(location: r.location - 1, length: 2) }
            storage.replaceCharacters(in: cut, with: "")
            tv.selectedRange = NSRange(location: min(cut.location, storage.length), length: 0)
            layoutAttachments()
            commit(NoteBodyTextBridge.markdown(from: storage))
        }

        private func viewFull(_ id: UUID) {
            guard let tv = textView,
                  let data = NoteImageLoader.shared.fullData(id, in: parent.modelContext),
                  let presenter = tv.nearestViewController?.topmostPresented else { return }
            let host = UIHostingController(rootView: NoteImageViewer(data: data))
            host.rootView = NoteImageViewer(data: data) { [weak host] in host?.dismiss(animated: true) }
            host.modalPresentationStyle = .fullScreen
            presenter.present(host, animated: true)
        }
    }
}

extension UIView {
    var nearestViewController: UIViewController? {
        var r: UIResponder? = self
        while let next = r?.next {
            if let vc = next as? UIViewController { return vc }
            r = next
        }
        return nil
    }
}

extension UIViewController {
    var topmostPresented: UIViewController {
        var vc = self
        while let p = vc.presentedViewController, !p.isBeingDismissed { vc = p }
        return vc
    }
}
#endif
