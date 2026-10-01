import SwiftUI
import DorisCore

/// Lightweight markdown renderer using SwiftUI's built-in `AttributedString(markdown:)` parser.
/// Body images (`NoteImageMarkup` lines) show as images between the text.
public struct MarkdownText: View {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public var body: some View {
        let parts = Self.parts(raw)
        if parts.count == 1, case .text(let text) = parts[0] {
            render(text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text): render(text).frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let ref): NoteImageView(ref: ref)
                    }
                }
            }
        }
    }

    private func render(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }

    enum Part { case text(String), image(NoteImageRef) }

    /// Runs of text lines, split wherever an image line sits.
    static func parts(_ raw: String) -> [Part] {
        var parts: [Part] = []
        var run: [String] = []
        for line in raw.components(separatedBy: "\n") {
            if let ref = NoteImageMarkup.parse(line: line) {
                if !run.isEmpty { parts.append(.text(run.joined(separator: "\n"))); run = [] }
                parts.append(.image(ref))
            } else {
                run.append(line)
            }
        }
        if !run.isEmpty || parts.isEmpty { parts.append(.text(run.joined(separator: "\n"))) }
        return parts
    }
}
