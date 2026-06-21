import SwiftUI
import SwiftData
import DorisCore
#if canImport(AppKit)
import AppKit
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
    /// macOS uses a PLAIN `@State`, not `@FocusState`: the macOS rows are
    /// AppKit fields that manage first-responder themselves. `@FocusState`
    /// only retains a programmatically-set value when a SwiftUI
    /// `.focused()` modifier claims it — there is none on macOS, so the
    /// set reverted to nil and the new row never focused. iOS keeps
    /// `@FocusState` for its native `.focused()` modifier.
    #if os(macOS)
    @State private var focusedLine: Int?
    #else
    @FocusState private var focusedLine: Int?
    #endif

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
            // `axis: .vertical` lets a long item wrap onto multiple lines
            // instead of scrolling horizontally inside a single-line field.
            TextField("", text: textBinding(at: idx), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...8)
                .strikethrough(line.checked == true, color: .secondary)
                .foregroundStyle(line.checked == true
                                 ? Color.primary.opacity(0.45)
                                 : Color.primary)
                .focused($focusedLine, equals: idx)
                .onSubmit { insertLine(after: idx) }
            #endif

            // No Spacer: the field above fills the width (maxWidth .infinity);
            // a Spacer would split the slack and wrap the text too early.

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
    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
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
