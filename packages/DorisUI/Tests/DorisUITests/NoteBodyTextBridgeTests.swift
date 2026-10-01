import XCTest
import DorisCore
@testable import DorisUI

/// The body editor loads Markdown into a text view and writes it back on
/// every keystroke. If that round trip changed anything, merely opening a
/// note would rewrite it — so it must be exact.
@MainActor
final class NoteBodyTextBridgeTests: XCTestCase {
    private let attrs: [NSAttributedString.Key: Any] = [:]
    private func img(_ size: NoteImageSize = .medium) -> String { NoteImageMarkup.line(NoteImageRef(id: UUID(), size: size)) }

    func testRoundTripIsExact() {
        let bodies = [
            "",
            "plain text",
            "line one\n\nline three\n",
            img(),
            "标题\n\(img(.small))\n说明文字\n\(img(.full))",
            "\(img())\n\(img(.large))",                 // two images back to back
            "- [ ] 卧推\n\(img())\n- [x] 深蹲",            // checklist Markdown stays literal
            "**bold** `code` [link](https://x.y)\n\(img())\n",
        ]
        for body in bodies {
            let text = NoteBodyTextBridge.attributedString(markdown: body, attributes: attrs)
            XCTAssertEqual(NoteBodyTextBridge.markdown(from: text), body, body)
        }
    }

    func testEachImageIsOneCharacter() {
        let body = "a\n\(img())\nb"
        let text = NoteBodyTextBridge.attributedString(markdown: body, attributes: attrs)
        XCTAssertEqual(text.string, "a\n\u{FFFC}\nb")
        XCTAssertEqual(NoteBodyTextBridge.attachments(in: text).count, 1)
    }

    /// Text typed right beside an image (or an image dropped mid-line)
    /// still saves as separate lines, and the view is told where to break.
    func testImagesAlwaysSaveOnTheirOwnLine() {
        let ref = NoteImageRef(id: UUID(), size: .large)
        let text = NSMutableAttributedString(string: "before")
        text.append(NSAttributedString(attachment: NoteImageTextAttachment(ref: ref)))
        text.append(NSAttributedString(string: "after"))
        XCTAssertEqual(NoteBodyTextBridge.markdown(from: text), "before\n\(NoteImageMarkup.line(ref))\nafter")
        XCTAssertEqual(NoteBodyTextBridge.lineBreakFixes(in: text), [7, 6])   // after the image, then before it
    }

    /// Text typed right after an image can inherit its attachment attribute
    /// (UIKit's typing attributes); it must still save as text.
    func testTextCarryingTheAttachmentAttributeIsText() {
        let ref = NoteImageRef(id: UUID(), size: .small)
        let a = NoteImageTextAttachment(ref: ref)
        let text = NSMutableAttributedString(attachment: a)
        text.append(NSAttributedString(string: "\nhi", attributes: [.attachment: a]))
        XCTAssertEqual(NoteBodyTextBridge.markdown(from: text), "\(NoteImageMarkup.line(ref))\nhi")
        XCTAssertEqual(NoteBodyTextBridge.lineBreakFixes(in: text), [])
    }

    /// Attachment characters that aren't ours (pasted rich content) carry
    /// nothing to save.
    func testForeignAttachmentsAreDropped() {
        let text = NSMutableAttributedString(string: "x")
        text.append(NSAttributedString(attachment: NSTextAttachment()))
        text.append(NSAttributedString(string: "y"))
        XCTAssertEqual(NoteBodyTextBridge.markdown(from: text), "xy")
    }

    /// Only a whole image line typed or pasted as text turns into an image.
    func testTextImageLineDetection() {
        let line = img()
        XCTAssertTrue(NoteBodyTextBridge.hasTextImageLine(NSAttributedString(string: "a\n\(line)\nb")))
        XCTAssertFalse(NoteBodyTextBridge.hasTextImageLine(NSAttributedString(string: "about doris-image: links")))
        XCTAssertFalse(NoteBodyTextBridge.hasTextImageLine(NSAttributedString(string: "inline \(line) here")))
    }

    /// The reading view splits text runs around image lines.
    func testMarkdownPreviewParts() {
        let ref = NoteImageRef(id: UUID(), size: .large)
        let parts = MarkdownText.parts("a\nb\n\(NoteImageMarkup.line(ref))\nc")
        XCTAssertEqual(parts.count, 3)
        guard case .text("a\nb") = parts[0], case .image(ref) = parts[1], case .text("c") = parts[2] else {
            return XCTFail("\(parts)")
        }
        XCTAssertEqual(MarkdownText.parts("plain").count, 1)
    }

    /// Images added with no editor to take them go at the end — above a
    /// checklist's trailing blank item.
    func testAppendingImages() {
        let ref = NoteImageRef(id: UUID())
        let line = NoteImageMarkup.line(ref)
        XCTAssertEqual(NoteImageInsertion.appending([ref], to: "", checklist: false), line)
        XCTAssertEqual(NoteImageInsertion.appending([ref], to: "text\n", checklist: false), "text\n\(line)")
        XCTAssertEqual(NoteImageInsertion.appending([ref], to: "- [ ] a\n- [ ] ", checklist: true), "- [ ] a\n\(line)\n- [ ] ")
        XCTAssertEqual(NoteImageInsertion.appending([ref], to: "- [ ] a", checklist: true), "- [ ] a\n\(line)")
    }

    func testPasteRuleTellsProseFromALink() {
        XCTAssertFalse(NoteImagePasteRule.isProse("https://example.com/a.png"))
        XCTAssertFalse(NoteImagePasteRule.isProse("  https://example.com/a.png\n"))
        XCTAssertTrue(NoteImagePasteRule.isProse("握距略宽于肩 下放到乳头连线"))
        XCTAssertTrue(NoteImagePasteRule.isProse("line one\nline two"))
    }
}
