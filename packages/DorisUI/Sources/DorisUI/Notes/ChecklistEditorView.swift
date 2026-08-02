import SwiftUI
import SwiftData
import DorisCore
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Renders the note's `bodyMarkdown` as a list of editable rows.
/// **Same single source of truth** as the plain-text editor: every row
/// in this view IS a line of `bodyMarkdown`. Switching the parent's
/// `isChecklist` toggle only changes how that text is rendered (linear
/// `TextEditor` vs this row-by-row checklist view) — no parallel
/// storage, no content loss when flipping back and forth.
///
/// Line grammar:
///   - `- [ ] foo`  → unchecked task with text "foo"
///   - `- [x] foo`  → checked task with text "foo" (also accepts `[X]`)
///   - `foo`        → "loose" line: rendered with a dotted-circle "no
///                    checkbox" indicator. Tap the indicator to promote
///                    it to a real (unchecked) task.
public struct ChecklistEditorView: View {
    @Bindable public var note: Note
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    /// Index of the checklist row whose text field should hold the
    /// keyboard. Set right after inserting a row so the cursor lands in
    /// the freshly-created item (Enter / "Add item" both route here).
    ///
    /// A PLAIN `@State`, not `@FocusState`, on BOTH platforms: each row is an
    /// AppKit (macOS) / UIKit (iOS) representable field that drives its own
    /// first responder from the `isFocused` input. `@FocusState` only retains
    /// a programmatically-set value when a SwiftUI `.focused()` modifier
    /// claims it — there is none here, so the set would revert to nil and a
    /// freshly-inserted row would never grab the keyboard.
    @State private var focusedLine: Int?

    public init(note: Note) {
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                row(at: idx, line: line)
            }
            addButton
                .padding(.top, 4)
        }
        // Focus ring clicked for a SUB-task → land the caret on that line.
        // A notification (rather than an init parameter) because it must also
        // work when this note is ALREADY open: `onAppear` wouldn't fire again,
        // so the caret would never move.
        .onReceive(NotificationCenter.default.publisher(for: .dorisOpenNote)) { n in
            guard n.object as? UUID == note.id else { return }
            focusSubtaskLine(n.userInfo?["subtask"] as? String)
        }
    }

    /// Land the caret on the sub-task the focus ring pointed at. Matched on
    /// trimmed text (the stored session text came from the same parse), and
    /// deferred a runloop so the row's field exists to take first responder.
    private func focusSubtaskLine(_ subtask: String?) {
        guard let wanted = subtask?.trimmingCharacters(in: .whitespaces),
              !wanted.isEmpty else { return }
        guard let idx = lines.firstIndex(where: {
            $0.text.trimmingCharacters(in: .whitespaces) == wanted
        }) else { return }
        DispatchQueue.main.async { focusedLine = idx }
    }

    /// Live re-parse from `note.bodyMarkdown` — never store derived
    /// state, so external edits / reverts always show through.
    private var lines: [Line] { Line.parseAll(note.bodyMarkdown) }

    @ViewBuilder
    private func row(at idx: Int, line: Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Checkbox / promote button
            Button {
                toggleCheck(at: idx)
            } label: {
                Image(systemName: checkboxIcon(for: line.checked))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(checkboxColor(for: line.checked))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(checkboxHelp(for: line.checked))

            #if os(macOS)
            // AppKit-backed field: SwiftUI's TextField can't intercept
            // the field editor's editing keys (Return / Backspace are
            // consumed before .onKeyPress sees them), so Return-to-add
            // and Backspace-on-empty-to-merge need the NSTextField
            // delegate. Wraps long text + reports its height.
            ChecklistItemField(
                text: textBinding(at: idx),
                checked: line.checked == true,
                colorScheme: colorScheme,
                isFocused: focusedLine == idx,
                onFocusChange: { gained in
                    if gained { focusedLine = idx }
                    else if focusedLine == idx { focusedLine = nil }
                },
                onSubmit: { insertLine(after: idx) },
                onDeleteEmpty: {
                    let arr = lines
                    guard idx > 0, idx < arr.count, arr[idx].text.isEmpty else { return }
                    backspaceMergeIntoPrevious(at: idx)
                },
                onMoveUp:   { moveFocus(to: idx - 1) },
                onMoveDown: { moveFocus(to: idx + 1) }
            )
            // Width-constrain so it wraps to the available space (reporting
            // its multi-line height) rather than growing horizontally.
            .frame(maxWidth: .infinity, alignment: .leading)
            #else
            // UIKit-backed field (mirrors the macOS ChecklistItemField). A
            // plain SwiftUI TextField can't do what we need: with
            // `axis: .vertical` Return inserts a newline (never fires
            // onSubmit), and there's no hook for Backspace-on-empty. A
            // non-scrolling UITextView subclass wraps long items AND lets us
            // intercept Return → new item and Backspace-on-empty → merge up.
            ChecklistItemFieldIOS(
                text: textBinding(at: idx),
                checked: line.checked == true,
                isFocused: focusedLine == idx,
                onFocusChange: { gained in
                    if gained { focusedLine = idx }
                    else if focusedLine == idx { focusedLine = nil }
                },
                onSubmit: { insertLine(after: idx) },
                onDeleteEmpty: {
                    let arr = lines
                    guard idx > 0, idx < arr.count, arr[idx].text.isEmpty else { return }
                    backspaceMergeIntoPrevious(at: idx)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif

            // No Spacer: the field above fills the width (maxWidth .infinity);
            // a Spacer would split the slack and wrap the text too early.

            // Focus (pomodoro) on this sub-task — a small timer menu (15/25/45).
            // Only for lines that have text (a loose empty row isn't a task).
            if !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                Menu {
                    ForEach([15, 25, 45], id: \.self) { m in
                        Button(L("\(m) min", "\(m) 分钟")) {
                            FocusTimer.shared.start(
                                noteID: note.id, title: note.title,
                                subtask: line.text, minutes: m
                            )
                        }
                    }
                } label: {
                    Image(systemName: "timer")
                        #if os(macOS)
                        .font(.system(size: 11))
                        #else
                        // Bigger on iOS: this is a touch target, not a
                        // pointer target.
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        #endif
                        .foregroundStyle(
                            FocusTimer.shared.isFocused(noteID: note.id, subtask: line.text)
                                ? CyberPalette.neonPink
                                : Color.primary.opacity(0.3)
                        )
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                #endif
                .help(L("Focus on this item", "专注此条"))
            }

            Button(role: .destructive) {
                removeLine(at: idx)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help(L("Remove this line", "删除此行"))
        }
    }

    private var addButton: some View {
        Button {
            insertLine(after: lines.count - 1)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(CyberPalette.neonCyan.opacity(0.75))
                    .font(.system(size: 12, weight: .semibold))
                Text(L("Add item", "新增条目"))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editing

    #if os(macOS)
    /// Move keyboard focus to an adjacent checklist item (↑/↓). Bounds-checked
    /// and deferred a runloop — setting focus synchronously from inside the
    /// field editor's key handling doesn't reliably move the first responder
    /// (same reason insertLine / backspaceMergeIntoPrevious defer).
    private func moveFocus(to index: Int) {
        guard lines.indices.contains(index) else { return }
        DispatchQueue.main.async { focusedLine = index }
    }
    #endif

    private func textBinding(at idx: Int) -> Binding<String> {
        Binding(
            get: {
                let arr = lines
                return idx < arr.count ? arr[idx].text : ""
            },
            set: { newText in
                var arr = lines
                guard idx < arr.count else { return }
                arr[idx].text = newText
                writeBack(arr)
            }
        )
    }

    private func toggleCheck(at idx: Int) {
        var arr = lines
        guard idx < arr.count else { return }
        switch arr[idx].checked {
        case nil:    arr[idx].checked = false   // loose → unchecked task
        case false?: arr[idx].checked = true    // unchecked → checked
        case true?:  arr[idx].checked = false   // checked → unchecked
        }
        writeBack(arr)
        syncNoteDone(from: arr)
    }

    private func insertLine(after idx: Int) {
        var arr = lines
        let insertAt = min(max(idx + 1, 0), arr.count)
        arr.insert(Line(checked: false, text: ""), at: insertAt)
        writeBack(arr)
        syncNoteDone(from: arr)
        // Land the cursor in the row we just created. Deferred to the
        // next runloop tick so the freshly-rendered TextField exists
        // before we ask for focus.
        DispatchQueue.main.async { focusedLine = insertAt }
    }

    private func removeLine(at idx: Int) {
        var arr = lines
        guard idx < arr.count else { return }
        arr.remove(at: idx)
        // Always keep at least one row to type into; collapsing to 0
        // makes the empty state visually awkward (just a Plus button).
        if arr.isEmpty { arr.append(Line(checked: false, text: "")) }
        writeBack(arr)
        syncNoteDone(from: arr)
    }

    /// Backspace on an empty row: drop the row and land the cursor at
    /// the end of the previous one (caller guarantees idx > 0). The
    /// previous row keeps its text; @FocusState moving to idx-1 places
    /// the insertion point there.
    private func backspaceMergeIntoPrevious(at idx: Int) {
        var arr = lines
        guard idx > 0, idx < arr.count else { return }
        arr.remove(at: idx)
        writeBack(arr)
        syncNoteDone(from: arr)
        DispatchQueue.main.async { focusedLine = idx - 1 }
    }

    private func writeBack(_ arr: [Line]) {
        note.bodyMarkdown = Line.serialize(arr)
        note.touch()
    }

    /// One-shot completion trigger — an *action*, not a binding. Only
    /// called from structural checklist edits (toggle / add / remove),
    /// never from plain text typing, so a manually-set done state is
    /// never silently overridden mid-keystroke. Two rules:
    ///   • adding / having an open task un-completes a done note
    ///   • ticking the last open task completes the note
    /// Notes with no checkbox tasks (only loose lines) are left alone.
    private func syncNoteDone(from arr: [Line]) {
        let tasks = arr.filter { $0.checked != nil }
        guard !tasks.isEmpty else { return }
        let allDone = tasks.allSatisfy { $0.checked == true }
        if allDone && !note.done {
            note.done = true
            note.completedAt = Date()
            note.touch()
            // All sub-tasks ticked → celebrate (the whole note is done).
            Task { @MainActor in HeroEvents.shared.celebrate() }
        } else if !allDone && note.done {
            note.done = false
            note.completedAt = nil
            note.touch()
        }
    }

    // MARK: - Checkbox visuals

    private func checkboxIcon(for checked: Bool?) -> String {
        switch checked {
        case nil:    return "circle.dotted"        // loose line, not yet a task
        case false?: return "square"               // unchecked task
        case true?:  return "checkmark.square.fill" // checked task
        }
    }

    private func checkboxColor(for checked: Bool?) -> Color {
        switch checked {
        case nil:    return Color.primary.opacity(0.30)
        case false?: return Color.primary.opacity(0.55)
        case true?:  return CyberPalette.neonCyan
        }
    }

    private func checkboxHelp(for checked: Bool?) -> String {
        switch checked {
        case nil:    return L("Promote to task", "提升为任务")
        case false?: return L("Mark done", "标记完成")
        case true?:  return L("Mark not done", "取消完成")
        }
    }
}

#if os(macOS)

/// Make `tf` the first responder and drop the caret at the END of its
/// text, retrying briefly if the view isn't in a window yet.
///
/// Why the retry: a freshly-created field inside the menu-bar **panel**
/// (NSPanel hosting) has a `nil` `window` for a few runloop ticks while
/// SwiftUI lays it out. The earlier single-shot attempt bailed on the
/// nil window and never tried again, so the new row never got the caret
/// (Enter created the row but focus was lost). In a regular NSWindow the
/// window was always ready, which is why it only broke in the dropdown.
///
/// "Caret at end" gives both behaviors we want for free: an empty new
/// row → caret at position 0 (the start); a backspace-merge target with
/// text → caret at the end.
func dorisFocusFieldToEnd(_ tf: NSTextField, tries: Int = 8) {
    DispatchQueue.main.async {
        guard let window = tf.window else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    dorisFocusFieldToEnd(tf, tries: tries - 1)
                }
            }
            return
        }
        // Already the focused field → leave the caret alone (don't yank
        // it to the end while the user is typing mid-string).
        guard window.firstResponder !== tf.currentEditor() else { return }
        window.makeFirstResponder(tf)
        if let editor = tf.currentEditor() {
            let end = (tf.stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
    }
}

// MARK: - macOS checklist item field (AppKit)

/// Self-sizing, word-wrapping NSTextField. Reports its wrapped height to
/// SwiftUI by refreshing `preferredMaxLayoutWidth` from its actual width
/// on each layout pass and invalidating its intrinsic size.
final class WrappingTextField: NSTextField {
    /// Extra height added above and below the text, so the field's clickable
    /// / editable area is taller than the glyphs themselves.
    ///
    /// An `NSTextField` is otherwise exactly text-high, which left the row's
    /// surrounding padding as dead space: clicking a hair above or below the
    /// characters hit the row, not the field, so it neither placed a caret
    /// nor started editing. The text stays vertically centred in the taller
    /// box (see `InsetTextFieldCell`).
    var verticalPadding: CGFloat = 0 {
        didSet {
            (cell as? InsetTextFieldCell)?.verticalPadding = verticalPadding
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    /// Report the WRAPPED height for the current width. `NSTextField`'s own
    /// `intrinsicContentSize` doesn't reliably reflect wrapping even with
    /// `preferredMaxLayoutWidth` set, so compute it explicitly via the cell —
    /// this is what makes the row grow to fit multi-line text instead of
    /// clipping at one line.
    override var intrinsicContentSize: NSSize {
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        guard width > 0, let cell else { return super.intrinsicContentSize }
        let h = cell.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(h) + verticalPadding * 2)
    }
}

/// Cell that keeps its text vertically centred inside a field made taller
/// than the text (see `WrappingTextField.verticalPadding`). All four rects
/// have to agree — drawing, editing, and selection each ask separately, and
/// missing one puts the caret somewhere other than the glyphs.
final class InsetTextFieldCell: NSTextFieldCell {
    var verticalPadding: CGFloat = 0

    private func inset(_ rect: NSRect) -> NSRect {
        guard verticalPadding > 0 else { return rect }
        let textHeight = cellSize(forBounds:
            NSRect(x: 0, y: 0, width: rect.width, height: .greatestFiniteMagnitude)).height
        // Centre the text in whatever slack the padding created. Clamped to
        // the frame so a wrapped field that already fills its box keeps every
        // line rather than losing the last one.
        let h = min(rect.height, ceil(textHeight))
        return NSRect(x: rect.minX,
                      y: rect.minY + (rect.height - h) / 2,
                      width: rect.width,
                      height: h)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        inset(super.titleRect(forBounds: rect))
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: inset(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: inset(rect), in: controlView,
                   editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: inset(rect), in: controlView,
                     editor: editor, delegate: delegate, start: start, length: length)
    }
}

/// Editable checklist item backed by AppKit so we can intercept the
/// field editor's command keys:
///   • Return  → `onSubmit` (new item)
///   • Backspace on an empty field → `onDeleteEmpty` (merge up)
/// SwiftUI's TextField can't do this — the field editor consumes those
/// keys before `.onKeyPress` runs.
struct ChecklistItemField: NSViewRepresentable {
    @Binding var text: String
    var checked: Bool
    /// Pinned to the field's appearance so `.labelColor` never resolves to
    /// the wrong light/dark value mid-update (the flicker-to-invisible bug).
    var colorScheme: ColorScheme
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Void
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WrappingTextField {
        let tf = WrappingTextField()
        tf.isEditable = true
        tf.isSelectable = true
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: NSFont.systemFontSize)
        tf.lineBreakMode = .byWordWrapping
        tf.usesSingleLineMode = false
        tf.maximumNumberOfLines = 0
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        tf.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        tf.delegate = context.coordinator
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        context.coordinator.installArrowMonitor(for: tf)
        return tf
    }

    static func dismantleNSView(_ nsView: WrappingTextField, coordinator: Coordinator) {
        coordinator.removeArrowMonitor()
    }

    func updateNSView(_ tf: WrappingTextField, context: Context) {
        let c = context.coordinator
        c.parent = self
        let appName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if tf.appearance?.name != appName { tf.appearance = NSAppearance(named: appName) }
        if tf.stringValue != text { tf.stringValue = text }
        // Only re-color when `checked` flips — NSColor comparison is
        // unreliable for dynamic/alpha colors, so the old guard re-assigned
        // (and redrew) every pass, flickering the row on unrelated refreshes.
        if c.appliedChecked != checked {
            c.appliedChecked = checked
            tf.textColor = checked ? NSColor.labelColor.withAlphaComponent(0.45) : .labelColor
        }

        // Become first responder when SwiftUI marks this row focused —
        // and drop the cursor at the END. Retries until the view is in a
        // window (crucial inside the menu-bar panel — see helper).
        if isFocused { dorisFocusFieldToEnd(tf) }
    }

    /// Report the WRAPPED height at SwiftUI's proposed width so a long
    /// sub-task grows the row to show all lines instead of clipping to one.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WrappingTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width != .infinity else { return nil }
        if abs(nsView.preferredMaxLayoutWidth - width) > 0.5 {
            nsView.preferredMaxLayoutWidth = width
            nsView.invalidateIntrinsicContentSize()
        }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ChecklistItemField
        /// Last-applied `checked` so we only re-color on an actual flip.
        var appliedChecked: Bool?
        init(_ parent: ChecklistItemField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
        func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocusChange(true) }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocusChange(false) }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
                parent.onDeleteEmpty()
                return true
            }
            return false
        }

        /// ↑/↓ switch between checklist items. Caught with a local key
        /// monitor (before the field editor turns them into caret moves),
        /// only while THIS field is being edited. Mirrors TodoTitleField.
        var arrowMonitor: Any?

        func installArrowMonitor(for field: NSTextField) {
            guard arrowMonitor == nil else { return }
            arrowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak field] event in
                guard let self, let field,
                      let editor = field.currentEditor(),
                      field.window?.firstResponder === editor,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return event }
                switch event.keyCode {
                case 126: self.parent.onMoveUp();   return nil   // ↑
                case 125: self.parent.onMoveDown(); return nil   // ↓
                default:  return event
                }
            }
        }

        func removeArrowMonitor() {
            if let m = arrowMonitor { NSEvent.removeMonitor(m); arrowMonitor = nil }
        }

        deinit { removeArrowMonitor() }
    }
}

#endif // os(macOS)

#if os(iOS)

// MARK: - iOS checklist item field (UIKit)

/// Make `tv` first responder with the caret at the END, retrying briefly if
/// the view isn't in a window yet — a freshly-inserted row's UITextView can
/// have a nil `window` for a few runloop ticks, and a single shot would
/// silently skip focusing it. Mirrors the macOS `dorisFocusFieldToEnd`.
func dorisFocusTextViewToEnd(_ tv: UITextView, tries: Int = 6) {
    DispatchQueue.main.async {
        guard !tv.isFirstResponder else { return }
        guard tv.window != nil else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    dorisFocusTextViewToEnd(tv, tries: tries - 1)
                }
            }
            return
        }
        tv.becomeFirstResponder()
        let end = (tv.text as NSString).length
        tv.selectedRange = NSRange(location: end, length: 0)
    }
}

/// Non-scrolling `UITextView` subclass that reports a Backspace pressed
/// while the field is empty. That's the reliable way to catch
/// "delete on an empty row" — the delegate's `shouldChangeTextIn` doesn't
/// fire for a backspace when there's nothing left to delete.
final class BackspaceReportingTextView: UITextView {
    var onBackspaceWhenEmpty: () -> Void = {}
    override func deleteBackward() {
        if text.isEmpty {
            onBackspaceWhenEmpty()
            return
        }
        super.deleteBackward()
    }
}

/// Editable checklist item for iOS, backed by a non-scrolling `UITextView`
/// so long items WRAP (matching macOS) while we intercept the editing keys
/// a SwiftUI `TextField` can't:
///   • Return             → onSubmit      (new item below)
///   • Backspace on empty → onDeleteEmpty (merge into the previous row)
/// Focus is driven by `isFocused` (the parent's `@State`), mirroring the
/// macOS `ChecklistItemField`. Checked items dim via text color — same as
/// macOS (which also doesn't strike through).
struct ChecklistItemFieldIOS: UIViewRepresentable {
    @Binding var text: String
    var checked: Bool
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BackspaceReportingTextView {
        let tv = BackspaceReportingTextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false            // grow to fit + word-wrap
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true   // track Dynamic Type live
        tv.returnKeyType = .next
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.onBackspaceWhenEmpty = { [weak c = context.coordinator] in c?.parent.onDeleteEmpty() }
        // Hug content vertically so the row is exactly as tall as its text.
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: BackspaceReportingTextView, context: Context) {
        context.coordinator.parent = self

        // NEVER touch the text (or the responder) while an input method is
        // mid-composition. `markedTextRange` is non-nil exactly then — the
        // Pinyin/Kana/Handwriting buffer that hasn't been committed yet.
        //
        // `tv.text` includes that uncommitted buffer while the binding holds
        // only what's been committed, so the two ALWAYS differ during
        // composition and this assignment would wipe it — the composition
        // collapses to raw letters, as if Return had been pressed mid-word.
        // Any parent re-render was enough to trigger it.
        let isComposing = tv.markedTextRange != nil
        if !isComposing, tv.text != text { tv.text = text }

        let color: UIColor = checked ? UIColor.label.withAlphaComponent(0.45) : .label
        if tv.textColor != color { tv.textColor = color }
        // Become first responder when the parent marks this row focused
        // (e.g. right after Enter inserts a new row), caret at the end.
        if isFocused, !tv.isFirstResponder, !isComposing {
            dorisFocusTextViewToEnd(tv)
        }
    }

    /// Report the wrapped height at SwiftUI's proposed width so the row grows
    /// to fit multi-line text instead of clipping.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BackspaceReportingTextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width != .infinity else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChecklistItemFieldIOS
        init(_ parent: ChecklistItemFieldIOS) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            // Don't publish a half-composed input method buffer. While
            // `markedTextRange` is set the text is provisional (raw pinyin,
            // kana, handwriting candidates); writing it upward would persist
            // and sync gibberish, and every write re-renders the view that
            // owns this field — the churn that broke composition in the first
            // place. UIKit calls this again the moment the candidate is
            // committed, with no marked range, so nothing is lost.
            guard tv.markedTextRange == nil else { return }
            parent.text = tv.text
        }
        func textViewDidBeginEditing(_ tv: UITextView) { parent.onFocusChange(true) }
        func textViewDidEndEditing(_ tv: UITextView) { parent.onFocusChange(false) }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            // Return → new item (swallow the newline instead of inserting it).
            if text == "\n" {
                parent.onSubmit()
                return false
            }
            // Multi-line paste / dictation: never let a raw "\n" reach the item
            // text — the shared parser splits bodyMarkdown on "\n", so an
            // embedded newline would explode one paste into phantom "loose"
            // rows. Flatten newlines to spaces so the paste stays in this item.
            if text.contains("\n") {
                let flat = text.replacingOccurrences(of: "\n", with: " ")
                let updated = (tv.text as NSString).replacingCharacters(in: range, with: flat)
                tv.text = updated
                parent.text = updated
                let caret = range.location + (flat as NSString).length
                tv.selectedRange = NSRange(location: caret, length: 0)
                return false
            }
            return true
        }
    }
}

#endif // os(iOS)

// MARK: - Line model (parse / serialize markdown checkbox syntax)

private struct Line {
    var checked: Bool?  // nil = loose text (no checkbox prefix)
    var text: String

    static func parseAll(_ body: String) -> [Line] {
        // Empty body still gives one empty editable row so the user has
        // something to type into.
        if body.isEmpty { return [Line(checked: false, text: "")] }
        return body.components(separatedBy: "\n").map(parse)
    }

    static func parse(_ raw: String) -> Line {
        if raw.hasPrefix("- [ ] ") {
            return Line(checked: false, text: String(raw.dropFirst(6)))
        }
        if raw.hasPrefix("- [x] ") || raw.hasPrefix("- [X] ") {
            return Line(checked: true, text: String(raw.dropFirst(6)))
        }
        // Edge cases: "- [ ]" / "- [x]" with no trailing space (empty task)
        if raw == "- [ ]" { return Line(checked: false, text: "") }
        if raw == "- [x]" || raw == "- [X]" { return Line(checked: true, text: "") }
        return Line(checked: nil, text: raw)
    }

    static func serialize(_ lines: [Line]) -> String {
        lines.map { line -> String in
            switch line.checked {
            case nil:    return line.text
            case false?: return "- [ ] " + line.text
            case true?:  return "- [x] " + line.text
            }
        }.joined(separator: "\n")
    }
}
