import Foundation

/// Inline styles in a note body: bold, underline and a highlight in one of
/// three colours. Stored in the body text, line by line:
///
///     **bold**   <u>underline</u>   <mark red>highlight</mark>
///
/// Every line opens and closes its own marks, so a line can be read on its
/// own (the editors parse the body a line at a time, around image lines).
/// A mark only counts when it is closed later on the same line; anything
/// else is ordinary text. Text that would read as a mark is escaped with a
/// backslash when saved (`\*\*`, `\<u>`), and a backslash before `*`, `<`
/// or another backslash is doubled.
public enum NoteInlineMarkup {
    public enum Highlight: String, CaseIterable, Sendable {
        case red, green, yellow
    }

    public struct Style: Hashable, Sendable {
        public var bold = false
        public var underline = false
        public var highlight: Highlight?

        public init(bold: Bool = false, underline: Bool = false, highlight: Highlight? = nil) {
            self.bold = bold
            self.underline = underline
            self.highlight = highlight
        }

        public var isPlain: Bool { !bold && !underline && highlight == nil }
    }

    public struct Run: Hashable, Sendable {
        public var text: String
        public var style: Style

        public init(_ text: String, _ style: Style = Style()) {
            self.text = text
            self.style = style
        }
    }

    // MARK: - Reading

    /// One line of the body as styled runs. Adjacent runs never share a style.
    public static func parse(line: String) -> [Run] {
        guard line.contains("*") || line.contains("<") || line.contains("\\") else {
            return line.isEmpty ? [] : [Run(line)]
        }
        let chars = Array(line)
        var runs: [Run] = []
        var style = Style()
        var buffer = ""
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].text += buffer
            } else {
                runs.append(Run(buffer, style))
            }
            buffer = ""
        }
        func at(_ token: String, _ index: Int) -> Bool {
            let t = Array(token)
            guard index + t.count <= chars.count else { return false }
            return Array(chars[index..<(index + t.count)]) == t
        }
        /// Whether `token` appears unescaped after `index`.
        func closes(_ token: String, after index: Int) -> Bool {
            var j = index
            while j < chars.count {
                if chars[j] == "\\", j + 1 < chars.count { j += 2; continue }
                if at(token, j) { return true }
                j += 1
            }
            return false
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, "*<\\".contains(chars[i + 1]) {
                buffer.append(chars[i + 1]); i += 2; continue
            }
            if at("**", i) {
                if style.bold || closes("**", after: i + 2) {
                    flush(); style.bold.toggle(); i += 2; continue
                }
            } else if at("<u>", i), !style.underline, closes("</u>", after: i + 3) {
                flush(); style.underline = true; i += 3; continue
            } else if at("</u>", i), style.underline {
                flush(); style.underline = false; i += 4; continue
            } else if at("<mark ", i), style.highlight == nil,
                      let end = chars[(i + 6)...].firstIndex(of: ">"),
                      let colour = Highlight(rawValue: String(chars[(i + 6)..<end])),
                      closes("</mark>", after: end + 1) {
                flush(); style.highlight = colour; i = end + 1; continue
            } else if at("</mark>", i), style.highlight != nil {
                flush(); style.highlight = nil; i += 7; continue
            }
            buffer.append(c)
            i += 1
        }
        flush()
        return runs
    }

    /// The line's text with the marks taken out — for list excerpts,
    /// search and anything else that shows plain text.
    public static func plain(line: String) -> String {
        parse(line: line).map(\.text).joined()
    }

    /// A whole body with the marks taken out, line by line.
    public static func plain(_ body: String) -> String {
        guard body.contains("*") || body.contains("<") || body.contains("\\") else { return body }
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { plain(line: String($0)) }
            .joined(separator: "\n")
    }

    // MARK: - Writing

    /// One line from styled runs (no newlines in them). Marks nest in a
    /// fixed order — bold, underline, highlight — and all close at the end.
    ///
    /// Text is escaped only when it has to be: if the unescaped line already
    /// reads back as the same runs, that is what's saved. So opening a note
    /// whose text happens to contain `**` or `<u>` never rewrites it.
    public static func serialize(_ runs: [Run]) -> String {
        let merged = normalized(runs)
        let plain = write(merged, escaping: false)
        return parse(line: plain) == merged ? plain : write(merged, escaping: true)
    }

    private static func write(_ runs: [Run], escaping: Bool) -> String {
        var out = ""
        var open = Style()
        for run in runs {
            transition(from: open, to: run.style, into: &out)
            open = run.style
            out += escaping ? escape(run.text) : run.text
        }
        transition(from: open, to: Style(), into: &out)
        return out
    }

    /// Empty runs dropped, neighbours with the same style joined — the
    /// shape `parse` returns.
    private static func normalized(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        for run in runs where !run.text.isEmpty {
            if let last = out.last, last.style == run.style {
                out[out.count - 1].text += run.text
            } else {
                out.append(run)
            }
        }
        return out
    }

    private static func transition(from a: Style, to b: Style, into out: inout String) {
        // Levels, outermost first. Close from the innermost level that
        // differs, then open what `b` needs from there.
        let aLevels: [String?] = [a.bold ? "b" : nil, a.underline ? "u" : nil, a.highlight?.rawValue]
        let bLevels: [String?] = [b.bold ? "b" : nil, b.underline ? "u" : nil, b.highlight?.rawValue]
        guard let first = (0..<3).first(where: { aLevels[$0] != bLevels[$0] }) else { return }
        for level in stride(from: 2, through: first, by: -1) where aLevels[level] != nil {
            out += ["**", "</u>", "</mark>"][level]
        }
        for level in first...2 {
            guard let v = bLevels[level] else { continue }
            out += level == 0 ? "**" : level == 1 ? "<u>" : "<mark \(v)>"
        }
    }

    /// Literal text, made safe to read back as text.
    static func escape(_ text: String) -> String {
        guard text.contains("*") || text.contains("<") || text.contains("\\") else { return text }
        let chars = Array(text)
        var out = ""
        for (i, c) in chars.enumerated() {
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            switch c {
            case "\\" where next.map { "*<\\".contains($0) } ?? false:
                out += "\\\\"
            case "*" where next == "*" || prev == "*":
                out += "\\*"
            case "<" where ["<u>", "</u>", "<mark ", "</mark>"].contains(where: {
                String(chars[i...]).hasPrefix($0) }):
                out += "\\<"
            default:
                out.append(c)
            }
        }
        return out
    }
}
