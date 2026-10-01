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

/// Converts between the body's Markdown and what the text views edit.
///
/// Only images are special: each image line becomes one attachment
/// character, everything else stays literal text — Markdown syntax
/// included. That is the whole point of doing it this way rather than with
/// a rich-text editor: the stored body stays plain Markdown, round-trips
/// exactly, and the views stay ordinary text views (which is what keeps
/// input methods behaving).
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
                out.append(NSAttributedString(string: line, attributes: attributes))
            }
            if i < lines.count - 1 { out.append(NSAttributedString(string: "\n", attributes: attributes)) }
        }
        return out
    }

    /// Back to Markdown. Images always come out on a line of their own, even
    /// if the view momentarily has text beside one (mid-composition, say),
    /// so the stored body is valid whatever state the view is in.
    static func markdown(from text: NSAttributedString) -> String {
        var out = ""
        var afterImage = false
        let ns = text.string as NSString
        func appendText(_ piece: String) {
            guard !piece.isEmpty else { return }
            if afterImage && !piece.hasPrefix("\n") { out += "\n" }
            afterImage = false
            out += piece
        }
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let a = value as? NoteImageTextAttachment {
                // Only the attachment character itself is the image. Text
                // typed beside it can inherit the attribute (UIKit carries
                // it into the typing attributes); that is still text.
                var pending = ""
                for i in range.location..<(range.location + range.length) {
                    if ns.character(at: i) == 0xFFFC {
                        appendText(pending); pending = ""
                        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                        out += NoteImageMarkup.line(a.ref)
                        afterImage = true
                    } else {
                        pending += ns.substring(with: NSRange(location: i, length: 1))
                    }
                }
                appendText(pending)
            } else {
                // Attachment characters that aren't ours (rich content pasted
                // from elsewhere) have nothing to save — drop them.
                appendText(ns.substring(with: range).replacingOccurrences(of: attachmentChar, with: ""))
            }
        }
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
