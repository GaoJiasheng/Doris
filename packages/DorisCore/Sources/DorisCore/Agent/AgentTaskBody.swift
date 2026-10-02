import Foundation

/// A note body as agents see and edit it: checklist items, numbered, plus
/// everything else as notes.
///
/// Same line grammar as the editors (`ChecklistEditorView`): `- [ ] text` is
/// an open item, `- [x] text` a done one, any other line is loose text —
/// so an agent's edit looks exactly like one made by hand.
enum AgentTaskBody {
    struct Line: Equatable {
        /// nil for a loose line.
        var checked: Bool?
        var text: String

        static func parse(_ raw: String) -> Line {
            if raw.hasPrefix("- [ ] ") { return Line(checked: false, text: String(raw.dropFirst(6))) }
            if raw.hasPrefix("- [x] ") || raw.hasPrefix("- [X] ") { return Line(checked: true, text: String(raw.dropFirst(6))) }
            if raw == "- [ ]" { return Line(checked: false, text: "") }
            if raw == "- [x]" || raw == "- [X]" { return Line(checked: true, text: "") }
            return Line(checked: nil, text: raw)
        }

        var raw: String {
            switch checked {
            case nil: return text
            case false?: return "- [ ] " + text
            case true?: return "- [x] " + text
            }
        }

        /// A row with nothing in it — the checklist editor keeps one at the
        /// end to type into.
        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    struct Item: Equatable {
        /// 1-based, counting items only.
        var number: Int
        var done: Bool
        var text: String
    }

    static func lines(_ body: String) -> [Line] {
        body.isEmpty ? [] : body.components(separatedBy: "\n").map(Line.parse)
    }

    static func serialize(_ lines: [Line]) -> String {
        lines.map(\.raw).joined(separator: "\n")
    }

    /// The checklist items, skipping blank ones (an empty row is a place to
    /// type, not a step).
    static func items(in body: String) -> [Item] {
        var out: [Item] = []
        for line in lines(body) {
            guard let checked = line.checked, !line.isBlank else { continue }
            out.append(Item(number: out.count + 1, done: checked, text: line.text))
        }
        return out
    }

    /// Everything that isn't an item, with images shown as "[image]".
    static func notes(in body: String) -> String {
        let loose = lines(body).filter { $0.checked == nil }.map(\.text)
        return NoteImageMarkup.displayText(loose.joined(separator: "\n"), placeholder: "[image]")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A new body from notes and items: notes first, then the items.
    static func compose(notes: String?, items: [String]) -> String {
        var out: [String] = []
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            out.append(notes)
        }
        out += items.map { Line(checked: false, text: oneLine($0)).raw }
        return out.joined(separator: "\n")
    }

    /// Items added at the end — above a trailing blank row, so the row the
    /// user types into stays last.
    static func appending(items: [String], to body: String) -> String {
        insertAtEnd(items.map { Line(checked: false, text: oneLine($0)) }, into: body)
    }

    static func appending(notes: String, to body: String) -> String {
        let added = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !added.isEmpty else { return body }
        return insertAtEnd(added.components(separatedBy: "\n").map { Line(checked: nil, text: $0) }, into: body)
    }

    /// The body with item `number` ticked or unticked, or nil if there's no
    /// such item.
    static func setting(item number: Int, done: Bool, in body: String) -> String? {
        var all = lines(body)
        var seen = 0
        for i in all.indices {
            guard all[i].checked != nil, !all[i].isBlank else { continue }
            seen += 1
            if seen == number {
                all[i].checked = done
                return serialize(all)
            }
        }
        return nil
    }

    private static func insertAtEnd(_ added: [Line], into body: String) -> String {
        guard !added.isEmpty else { return body }
        var all = lines(body)
        var at = all.count
        while at > 0, all[at - 1].isBlank { at -= 1 }
        all.insert(contentsOf: added, at: at)
        return serialize(all)
    }

    /// An item is one line: a newline inside one would split it in two.
    private static func oneLine(_ s: String) -> String {
        s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
