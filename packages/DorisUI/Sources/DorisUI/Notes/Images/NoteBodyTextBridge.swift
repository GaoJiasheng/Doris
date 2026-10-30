import SwiftUI
import SwiftData
import DorisCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An image inside the body text view. Carries which image and how wide;
/// the bitmap and bounds are filled in by `NoteBodyTextBridge.layout`.
final class NoteImageTextAttachment: NSTextAttachment {
    var ref: NoteImageRef
    /// Drawing the "syncing" card because the bytes aren't here yet.
    var isPlaceholder = false

    init(ref: NoteImageRef) {
        self.ref = ref
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("not coded") }
}

/// Converts between the stored body and what the text views edit.
///
/// Each image line becomes one attachment character. Bold, underline and
/// highlight marks (`NoteInlineMarkup`) become styled runs — the marks
/// themselves never show — and are written back from the runs' style
/// attributes, a line at a time. Everything else is literal text.
@MainActor
enum NoteBodyTextBridge {
    static let attachmentChar = "\u{FFFC}"

    static func attributedString(markdown: String,
                                 attributes: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if let ref = NoteImageMarkup.parse(line: line) {
                let a = NSMutableAttributedString(attachment: NoteImageTextAttachment(ref: ref))
                a.addAttributes(attributes, range: NSRange(location: 0, length: a.length))
                out.append(a)
            } else {
                for run in NoteInlineMarkup.parse(line: line) {
                    out.append(NSAttributedString(string: run.text,
                                                  attributes: NoteRichText.attributes(run.style, base: attributes)))
                }
            }
            if i < lines.count - 1 { out.append(NSAttributedString(string: "\n", attributes: attributes)) }
        }
        return out
    }

    /// Back to the stored form. Images always come out on a line of their
    /// own, even if the view momentarily has text beside one (mid-
    /// composition, say), so the stored body is valid whatever state the
    /// view is in. Styled text closes its marks at the end of every line.
    static func markdown(from text: NSAttributedString) -> String {
        enum Piece { case text(String, NoteInlineMarkup.Style), newline, image(NoteImageRef) }
        var pieces: [Piece] = []
        let ns = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let image = attrs[.attachment] as? NoteImageTextAttachment
            let style = NoteRichText.style(of: attrs)
            var pending = ""
            func flush() {
                if !pending.isEmpty { pieces.append(.text(pending, style)); pending = "" }
            }
            for i in range.location..<(range.location + range.length) {
                let unit = ns.character(at: i)
                if unit == 0xFFFC {
                    flush()
                    // Only our attachment is an image. Text typed beside one
                    // can inherit the attribute (UIKit carries it into the
                    // typing attributes); that is still text. Attachments
                    // that aren't ours (rich paste) have nothing to save.
                    if let image { pieces.append(.image(image.ref)) }
                } else if unit == 0x0A {
                    flush(); pieces.append(.newline)
                } else {
                    pending += ns.substring(with: NSRange(location: i, length: 1))
                }
            }
            flush()
        }

        var out = ""
        var line: [NoteInlineMarkup.Run] = []
        var lineHasContent = false        // text or an image on the current line
        var afterImage = false
        func endLine() {
            out += NoteInlineMarkup.serialize(line)
            line = []
        }
        for piece in pieces {
            switch piece {
            case .text(let t, let style):
                if afterImage { out += "\n"; afterImage = false; lineHasContent = false }
                line.append(.init(t, style))
                lineHasContent = true
            case .newline:
                endLine()
                out += "\n"
                afterImage = false
                lineHasContent = false
            case .image(let ref):
                endLine()
                if lineHasContent { out += "\n" }
                out += NoteImageMarkup.line(ref)
                afterImage = true
                lineHasContent = true
            }
        }
        endLine()
        return out
    }

    /// Whether the view holds an image line as plain text — pasted Markdown
    /// copied from another note — that should be shown as the image.
    static func hasTextImageLine(_ text: NSAttributedString) -> Bool {
        let string = text.string
        guard string.contains("\(NoteImageMarkup.scheme):") else { return false }
        return string.components(separatedBy: "\n").contains { NoteImageMarkup.parse(line: $0) != nil }
    }

    /// Offsets, last first, where a newline must go so every image sits
    /// alone on its line — applied to the view itself once no composition
    /// is in progress.
    static func lineBreakFixes(in text: NSAttributedString) -> [Int] {
        let ns = text.string as NSString
        var fixes = Set<Int>()
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard value is NoteImageTextAttachment else { return }
            for i in range.location..<(range.location + range.length) where ns.character(at: i) == 0xFFFC {
                if i > 0, ns.character(at: i - 1) != 0x0A { fixes.insert(i) }
                if i + 1 < ns.length, ns.character(at: i + 1) != 0x0A { fixes.insert(i + 1) }
            }
        }
        return fixes.sorted(by: >)
    }

    /// Give an attachment its bitmap and size for a text column `width` wide.
    /// Returns whether it is still a placeholder (bytes not here yet).
    @discardableResult
    static func layout(_ a: NoteImageTextAttachment, width: CGFloat, context: ModelContext,
                       scale: CGFloat) -> Bool {
        let loader = NoteImageLoader.shared
        let w = max(40, (width * a.ref.size.widthFraction).rounded(.down))
        let h = (w * loader.aspect(a.ref.id, in: context)).rounded()
        if let img = loader.inlineImage(a.ref.id, size: CGSize(width: w, height: h), scale: scale, in: context) {
            a.image = img
            a.isPlaceholder = false
        } else {
            a.image = loader.placeholder(size: CGSize(width: w, height: h), text: NoteImageLoader.syncingText)
            a.isPlaceholder = true
        }
        a.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        return a.isPlaceholder
    }

    static func attachments(in text: NSAttributedString) -> [(NoteImageTextAttachment, NSRange)] {
        var found: [(NoteImageTextAttachment, NSRange)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let a = value as? NoteImageTextAttachment { found.append((a, range)) }
        }
        return found
    }
}
