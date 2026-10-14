#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import DorisCore

/// The note body editor: plain text, with images shown in place.
///
/// Replaces a SwiftUI `TextEditor`, which can't show an image. Paste or
/// drop an image and it lands on its own line at the cursor; click it to
/// pick a size, view it full size, or delete it. Everything that isn't an
/// image is ordinary text — the body stays Markdown (see
/// `NoteBodyTextBridge`).
public struct NoteBodyEditor: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var ctx
    var fontSize: CGFloat
    var inset: CGSize

    public init(note: Note, fontSize: CGFloat = NSFont.systemFontSize, inset: CGSize = CGSize(width: 6, height: 6)) {
        self.note = note
        self.fontSize = fontSize
        self.inset = inset
    }

    public var body: some View {
        NoteBodyTextViewMac(note: note, modelContext: ctx, fontSize: fontSize, inset: inset)
    }
}

final class NoteBodyNSTextView: NSTextView {
    var onImages: (([Data], Int?) -> Void)?
    var onWidthChange: (() -> Void)?
    /// Markdown for a range, so copying an image copies its line.
    var markdownForRange: ((NSRange) -> String)?

    private static let imageTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff,
                                                                     .init(UTType.jpeg.identifier),
                                                                     .init(UTType.heic.identifier)]

    /// Image bytes on a pasteboard: image files first (Finder copies,
    /// drags from Finder), then raw image data (screenshots, browsers).
    static func imageDatas(from pb: NSPasteboard) -> [Data] {
        let urlOpts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: urlOpts) as? [URL], !urls.isEmpty {
            return urls.compactMap { try? Data(contentsOf: $0) }
        }
        for t in imageTypes.dropFirst() {
            if let d = pb.data(forType: t) { return [d] }
        }
        return []
    }

    /// What ⌘V should insert as images, if anything. Image files always
    /// (Finder also puts their names on the pasteboard as text). Image data
    /// unless the pasteboard's text is real text — copying part of a page
    /// carries text plus pictures and means the text — rather than a lone
    /// link or file name riding along with a copied image.
    static func pastedImages(from pb: NSPasteboard) -> [Data] {
        let images = imageDatas(from: pb)
        guard !images.isEmpty else { return [] }
        let hasFiles = pb.canReadObject(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true,
                                                  .urlReadingContentsConformToTypes: [UTType.image.identifier]])
        if !hasFiles, let text = pb.string(forType: .string), NoteImagePasteRule.isProse(text) { return [] }
        return images
    }

    override func paste(_ sender: Any?) {
        let images = Self.pastedImages(from: .general)
        if !images.isEmpty { onImages?(images, nil); return }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        Self.imageTypes + super.acceptableDragTypes
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = Self.imageDatas(from: sender.draggingPasteboard)
        guard !images.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        onImages?(images, characterIndexForInsertion(at: point))
        return true
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let md = markdownForRange?(selectedRange()), md.contains(NoteImageMarkup.scheme) else {
            return super.writeSelection(to: pboard, types: types)
        }
        pboard.clearContents()
        return pboard.setString(md, forType: .string)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let old = frame.width
        super.setFrameSize(newSize)
        if abs(old - newSize.width) > 0.5 { onWidthChange?() }
    }

    // MARK: Drag to resize

    /// Where each image sits (view coordinates), from the coordinator.
    var imageFrames: () -> [ImageFrame] = { [] }
    /// The text column's width: an image's size is a share of it.
    var columnWidth: () -> CGFloat = { 300 }
    /// Live, while dragging: the image at `charIndex` should be this size.
    var onResize: ((Int, NoteImageSize) -> Void)?
    var onResizeEnded: (() -> Void)?

    struct ImageFrame {
        let charIndex: Int
        let rect: NSRect
        let size: NoteImageSize
    }

    private var hovered: ImageFrame?
    private var resizeTracking: NSTrackingArea?
    static let handleSide: CGFloat = 14

    private func handleRect(for frame: ImageFrame) -> NSRect {
        NSRect(x: frame.rect.maxX - Self.handleSide - 4, y: frame.rect.maxY - Self.handleSide - 4,
               width: Self.handleSide, height: Self.handleSide)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let resizeTracking { removeTrackingArea(resizeTracking) }
        // Always active: the notch dropdown and desktop card aren't key windows.
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        resizeTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        let frame = imageFrames().first { $0.rect.contains(p) }
        if frame?.charIndex != hovered?.charIndex || frame?.rect != hovered?.rect {
            if let old = hovered { setNeedsDisplay(old.rect.insetBy(dx: -2, dy: -2)) }
            hovered = frame
            if let frame { setNeedsDisplay(frame.rect.insetBy(dx: -2, dy: -2)) }
        }
        if let frame, handleRect(for: frame).insetBy(dx: -4, dy: -4).contains(p) {
            NSCursor.resizeLeftRight.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if let old = hovered { setNeedsDisplay(old.rect.insetBy(dx: -2, dy: -2)) }
        hovered = nil
    }

    /// The handle shows on the image under the pointer, so it's clear the
    /// image can be resized without cluttering every picture.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let hovered else { return }
        let r = handleRect(for: hovered)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        shadow.set()
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.95).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        // Two short diagonal strokes, the usual "drag this corner" mark.
        NSColor.black.withAlphaComponent(0.55).setStroke()
        for inset in [3.5, 7.0] as [CGFloat] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: r.maxX - 3, y: r.minY + inset))
            line.line(to: NSPoint(x: r.minX + inset, y: r.maxY - 3))
            line.lineWidth = 1.2
            line.lineCapStyle = .round
            line.stroke()
        }
    }

    /// Dragging the corner handle steps the image through the four sizes —
    /// the sizes a note stores, so it looks the same on the iPhone.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let frame = imageFrames().first(where: { handleRect(for: $0).insetBy(dx: -4, dy: -4).contains(p) }) else {
            return super.mouseDown(with: event)
        }
        var current = frame.size
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let q = convert(e.locationInWindow, from: nil)
            let fraction = max(0.05, (q.x - frame.rect.minX) / max(1, columnWidth()))
            let nearest = NoteImageSize.allCases.min {
                abs($0.widthFraction - fraction) < abs($1.widthFraction - fraction)
            } ?? current
            if nearest != current {
                current = nearest
                onResize?(frame.charIndex, nearest)
                hovered = imageFrames().first { $0.charIndex == frame.charIndex }
                needsDisplay = true
            }
            NSCursor.resizeLeftRight.set()
            if e.type == .leftMouseUp { break }
        }
        onResizeEnded?()
    }
}

struct NoteBodyTextViewMac: NSViewRepresentable {
    @Bindable var note: Note
    let modelContext: ModelContext
    var fontSize: CGFloat
    var inset: CGSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        // TextKit 1: mature, predictable attachment sizing.
        let tv = NoteBodyNSTextView(usingTextLayoutManager: false)
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isRichText = false          // images are handled here, not by NSTextView
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = inset
        tv.isAutomaticQuoteSubstitutionEnabled = false   // keep Markdown literal
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.typingAttributes = context.coordinator.baseAttributes
        tv.delegate = context.coordinator

        let c = context.coordinator
        c.textView = tv
        tv.onImages = { [weak c] datas, index in c?.insertImages(datas, at: index) }
        tv.onWidthChange = { [weak c] in c?.layoutAttachments() }
        tv.markdownForRange = { [weak c] range in c?.markdown(in: range) ?? "" }
        tv.imageFrames = { [weak c] in c?.imageFrames() ?? [] }
        tv.columnWidth = { [weak c] in c?.columnWidthForResize ?? 300 }
        tv.onResize = { [weak c] index, size in c?.resizeLive(at: index, to: size) }
        tv.onResizeEnded = { [weak c] in c?.commitCurrent() }
        tv.updateDragTypeRegistration()

        scroll.documentView = tv
        c.load(note.bodyMarkdown, noteID: note.id)
        c.observeInsertRequests()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        tv.textContainerInset = inset
        // Reload only for a change that didn't come from this view (another
        // note shown in the same slot, an edit synced from another device),
        // and never while the input method is composing.
        if c.noteID != note.id || (note.bodyMarkdown != c.lastMarkdown && !tv.hasMarkedText()) {
            c.load(note.bodyMarkdown, noteID: note.id)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteBodyTextViewMac
        weak var textView: NoteBodyNSTextView?
        var lastMarkdown = ""
        var noteID: UUID?
        private var fixing = false
        private var retry: Timer?
        private var insertObserver: NSObjectProtocol?
        /// Where the user last put the caret; nil until then, so an image
        /// added from the toolbar before any editing goes at the end.
        private var userSelection: NSRange?

        init(_ parent: NoteBodyTextViewMac) { self.parent = parent }

        deinit {
            if let insertObserver { NotificationCenter.default.removeObserver(insertObserver) }
        }

        /// "Insert image" from the toolbar lands at the cursor. Synchronous
        /// (queue nil) so the sender sees `handled`.
        func observeInsertRequests() {
            insertObserver = NotificationCenter.default.addObserver(
                forName: .dorisInsertNoteImages, object: nil, queue: nil) { [weak self] n in
                MainActor.assumeIsolated {
                    guard let self, let request = n.object as? NoteImageInsertion.Request,
                          request.noteID == self.parent.note.id, !request.handled,
                          let tv = self.textView, tv.window != nil else { return }
                    request.handled = true
                    let at = tv.window?.firstResponder === tv ? nil
                        : (self.userSelection?.location ?? tv.textStorage?.length ?? 0)
                    self.insertImages(request.datas, at: at)
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, tv.window?.firstResponder === tv else { return }
            userSelection = tv.selectedRange()
        }

        var baseAttributes: [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: parent.fontSize), .foregroundColor: NSColor.labelColor]
        }

        private var columnWidth: CGFloat {
            guard let tv = textView, let tc = tv.textContainer else { return 300 }
            return max(60, tc.containerSize.width - tc.lineFragmentPadding * 2)
        }

        func load(_ markdown: String, noteID: UUID) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let selection = tv.selectedRange()
            storage.setAttributedString(NoteBodyTextBridge.attributedString(markdown: markdown,
                                                                             attributes: baseAttributes))
            lastMarkdown = markdown
            if self.noteID == noteID {
                tv.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
            }
            self.noteID = noteID
            layoutAttachments()
        }

        func layoutAttachments() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let scale = tv.window?.backingScaleFactor ?? 2
            var waiting = false
            for (a, range) in NoteBodyTextBridge.attachments(in: storage) {
                if NoteBodyTextBridge.layout(a, width: columnWidth, context: parent.modelContext, scale: scale) {
                    waiting = true
                }
                tv.layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                tv.layoutManager?.invalidateDisplay(forCharacterRange: range)
            }
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

        func markdown(in range: NSRange) -> String {
            guard let storage = textView?.textStorage, range.length > 0 else { return "" }
            return NoteBodyTextBridge.markdown(from: storage.attributedSubstring(from: range))
        }

        // MARK: Editing

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage, !fixing else { return }
            // Don't publish a half-composed input method buffer (raw pinyin):
            // it would save and sync, and the note's re-sort on every letter
            // can rebuild the view mid-word. This fires again on commit.
            guard !tv.hasMarkedText() else { return }
            if NoteBodyTextBridge.hasTextImageLine(storage) {
                // An image line pasted or typed as text: show it as the
                // image, keeping the caret after what was pasted.
                let md = NoteBodyTextBridge.markdown(from: storage)
                let caret = min(tv.selectedRange().location, storage.length)
                let before = NoteBodyTextBridge.markdown(from: storage.attributedSubstring(from: NSRange(location: 0, length: caret)))
                load(md, noteID: noteID ?? parent.note.id)
                let newCaret = NoteBodyTextBridge.attributedString(markdown: before, attributes: [:]).length
                tv.setSelectedRange(NSRange(location: min(newCaret, storage.length), length: 0))
                commit(md)
                return
            }
            let fixes = NoteBodyTextBridge.lineBreakFixes(in: storage)
            if !fixes.isEmpty {
                fixing = true
                for at in fixes { storage.insert(NSAttributedString(string: "\n", attributes: baseAttributes), at: at) }
                fixing = false
            }
            commit(NoteBodyTextBridge.markdown(from: storage))
        }

        private func commit(_ md: String) {
            guard md != lastMarkdown else { return }
            lastMarkdown = md
            parent.note.bodyMarkdown = md
        }

        func insertImages(_ datas: [Data], at index: Int?) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let refs = datas.compactMap { NoteImageStore.add(imageData: $0, to: parent.note, in: parent.modelContext) }
            guard !refs.isEmpty else { NSSound.beep(); return }
            var at = index ?? tv.selectedRange().location
            at = min(max(0, at), storage.length)
            let insertion = NSMutableAttributedString()
            let ns = storage.string as NSString
            if at > 0, ns.character(at: at - 1) != 0x0A {
                insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            for (i, ref) in refs.enumerated() {
                if i > 0 { insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes)) }
                let a = NSMutableAttributedString(attachment: NoteImageTextAttachment(ref: ref))
                a.addAttributes(baseAttributes, range: NSRange(location: 0, length: a.length))
                insertion.append(a)
            }
            let target = NSRange(location: at, length: index == nil ? tv.selectedRange().length : 0)
            // Break after the image unless the line already ends there.
            let end = target.location + target.length
            if end >= ns.length || ns.character(at: end) != 0x0A {
                insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
            if tv.shouldChangeText(in: target, replacementString: insertion.string) {
                storage.replaceCharacters(in: target, with: insertion)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: at + insertion.length, length: 0))
            }
            layoutAttachments()
        }

        // MARK: Image menu

        func textView(_ textView: NSTextView, clickedOn cell: any NSTextAttachmentCellProtocol,
                      in cellFrame: NSRect, at charIndex: Int) {
            guard let a = cell.attachment as? NoteImageTextAttachment else { return }
            let id = a.ref.id
            let menu = NoteImageActions.menu(
                current: a.ref.size, canView: !a.isPlaceholder,
                onResize: { [weak self] size in self?.resize(at: charIndex, to: size) },
                onView: { [weak self] in
                    guard let self else { return }
                    NoteImageActions.openFullSize(id, in: self.parent.modelContext)
                },
                onDelete: { [weak self] in self?.deleteImage(at: charIndex) })
            menu.popUp(positioning: nil, at: NSPoint(x: cellFrame.minX, y: cellFrame.maxY + 4), in: textView)
        }

        // MARK: Drag to resize

        var columnWidthForResize: CGFloat { columnWidth }

        /// Where each image is drawn: it stands on its line's baseline.
        func imageFrames() -> [NoteBodyNSTextView.ImageFrame] {
            guard let tv = textView, let lm = tv.layoutManager, let storage = tv.textStorage else { return [] }
            let origin = tv.textContainerOrigin
            return NoteBodyTextBridge.attachments(in: storage).map { a, range in
                let glyph = lm.glyphIndexForCharacter(at: range.location)
                let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let loc = lm.location(forGlyphAt: glyph)
                let rect = NSRect(x: origin.x + line.minX + loc.x,
                                  y: origin.y + line.minY + loc.y - a.bounds.height,
                                  width: a.bounds.width, height: a.bounds.height)
                return .init(charIndex: range.location, rect: rect, size: a.ref.size)
            }
        }

        func resizeLive(at index: Int, to size: NoteImageSize) {
            guard let storage = textView?.textStorage, index < storage.length,
                  let a = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NoteImageTextAttachment
            else { return }
            a.ref.size = size
            layoutAttachments()
        }

        func commitCurrent() {
            guard let storage = textView?.textStorage else { return }
            commit(NoteBodyTextBridge.markdown(from: storage))
        }

        private func resize(at index: Int, to size: NoteImageSize) {
            guard let storage = textView?.textStorage, index < storage.length,
                  let a = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NoteImageTextAttachment
            else { return }
            a.ref.size = size
            layoutAttachments()
            commit(NoteBodyTextBridge.markdown(from: storage))
        }

        private func deleteImage(at index: Int) {
            guard let tv = textView, let storage = tv.textStorage, index < storage.length else { return }
            // Take the image's line break with it, so no blank line is left.
            let ns = storage.string as NSString
            var range = NSRange(location: index, length: 1)
            if index + 1 < ns.length, ns.character(at: index + 1) == 0x0A { range.length = 2 }
            else if index > 0, ns.character(at: index - 1) == 0x0A { range = NSRange(location: index - 1, length: 2) }
            if tv.shouldChangeText(in: range, replacementString: "") {
                storage.replaceCharacters(in: range, with: "")
                tv.didChangeText()
            }
        }
    }
}
#endif
