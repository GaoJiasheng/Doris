import SwiftUI
import SwiftData
import DorisCore

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

    /// Index of the checklist row whose text field should hold the
    /// keyboard. Set right after inserting a row so the cursor lands in
    /// the freshly-created item (Enter / "Add item" both route here).
    @FocusState private var focusedLine: Int?

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

            // `axis: .vertical` lets a long item wrap onto multiple
            // lines instead of scrolling horizontally inside a fixed
            // single-line field. `.firstTextBaseline` on the HStack
            // keeps the checkbox aligned to the first wrapped line.
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

            Spacer(minLength: 0)

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
