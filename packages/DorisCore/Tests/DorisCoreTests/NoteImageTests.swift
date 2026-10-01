import XCTest
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import DorisCore

final class NoteImageMarkupTests: XCTestCase {
    func testLineRoundTrips() {
        for size in NoteImageSize.allCases {
            let ref = NoteImageRef(id: UUID(), size: size)
            XCTAssertEqual(NoteImageMarkup.parse(line: NoteImageMarkup.line(ref)), ref)
        }
    }

    func testParsesHandWrittenAndToleratesNoise() {
        let id = UUID()
        // No size → default; alt text and surrounding spaces are fine.
        XCTAssertEqual(NoteImageMarkup.parse(line: "  ![杠铃](doris-image:\(id.uuidString))  "),
                       NoteImageRef(id: id, size: .default))
        XCTAssertEqual(NoteImageMarkup.parse(line: "![](doris-image:\(id.uuidString)?w=zz)")?.size, .default)
        // Not images of ours.
        XCTAssertNil(NoteImageMarkup.parse(line: "![](https://example.com/a.png)"))
        XCTAssertNil(NoteImageMarkup.parse(line: "see ![](doris-image:\(id.uuidString)) here"))
        XCTAssertNil(NoteImageMarkup.parse(line: "![](doris-image:not-a-uuid)"))
        XCTAssertNil(NoteImageMarkup.parse(line: "- [ ] 卧推 5x5"))
    }

    func testRefsAndDisplayText() {
        let a = NoteImageRef(id: UUID(), size: .small), b = NoteImageRef(id: UUID(), size: .full)
        let body = ["- [ ] 卧推", NoteImageMarkup.line(a), "手肘别外翻", NoteImageMarkup.line(b)].joined(separator: "\n")
        XCTAssertEqual(NoteImageMarkup.refs(in: body), [a, b])
        XCTAssertEqual(NoteImageMarkup.displayText(body, placeholder: "[图片]"),
                       "- [ ] 卧推\n[图片]\n手肘别外翻\n[图片]")
        XCTAssertEqual(NoteImageMarkup.displayText("plain", placeholder: "[图片]"), "plain")
    }
}

final class NoteImageEncoderTests: XCTestCase {
    private func png(width: Int, height: Int, alpha: Bool, opacity: CGFloat = 0.5) -> Data {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: alpha ? opacity : 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testDownscalesLongSideAndPicksFormat() throws {
        let big = try XCTUnwrap(NoteImageEncoder.encode(png(width: 4000, height: 1000, alpha: false)))
        XCTAssertEqual(big.width, NoteImageEncoder.maxPixel)
        XCTAssertEqual(big.height, 512)
        XCTAssertEqual(big.mimeType, "image/jpeg")

        let small = try XCTUnwrap(NoteImageEncoder.encode(png(width: 300, height: 200, alpha: false)))
        XCTAssertEqual([small.width, small.height], [300, 200], "never upscales")

        let clear = try XCTUnwrap(NoteImageEncoder.encode(png(width: 64, height: 64, alpha: true)))
        XCTAssertEqual(clear.mimeType, "image/png", "transparency must survive")

        // An alpha channel that is opaque everywhere (clipboard screenshots).
        let opaque = try XCTUnwrap(NoteImageEncoder.encode(png(width: 64, height: 64, alpha: true, opacity: 1)))
        XCTAssertEqual(opaque.mimeType, "image/jpeg")
    }

    func testRejectsNonImages() {
        XCTAssertNil(NoteImageEncoder.encode(Data("hello".utf8)))
    }
}

@MainActor
final class NoteImageStoreTests: XCTestCase {
    func testOrphansAreDeletedOnlyAfterGraceAndOnlyIfUnreferenced() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let ctx = container.mainContext
        let now = Date()
        let note = Note(title: "动作学习")
        ctx.insert(note)
        func image(age days: Double) -> Attachment {
            let a = Attachment(filename: "image.jpg", mimeType: "image/jpeg", byteCount: 3, relativePath: "", note: note)
            a.data = Data([1, 2, 3]); a.pixelWidth = 10; a.pixelHeight = 10
            a.createdAt = now.addingTimeInterval(-days * 86_400)
            ctx.insert(a)
            return a
        }
        let used = image(age: 30), oldOrphan = image(age: 30), freshOrphan = image(age: 1)
        let otherNote = Note(title: "copy")
        let usedElsewhere = image(age: 30)
        otherNote.bodyMarkdown = NoteImageMarkup.line(NoteImageRef(id: usedElsewhere.id))
        ctx.insert(otherNote)
        note.bodyMarkdown = "说明\n" + NoteImageMarkup.line(NoteImageRef(id: used.id))
        // Not a body image (pixelWidth 0) — e.g. a share-extension file: never touched.
        let legacy = Attachment(filename: "f.txt", mimeType: "text/plain", byteCount: 1, relativePath: "Attachments/f.txt")
        legacy.createdAt = now.addingTimeInterval(-90 * 86_400)
        ctx.insert(legacy)
        try ctx.save()

        NoteImageStore.purgeOrphans(context: ctx, now: now)

        let left = Set(try ctx.fetch(FetchDescriptor<Attachment>()).map(\.id))
        XCTAssertEqual(left, [used.id, freshOrphan.id, usedElsewhere.id, legacy.id])
        XCTAssertFalse(left.contains(oldOrphan.id))
    }

    /// An image pasted from note A into note B outlives A's deletion.
    func testDeletingANoteKeepsImagesOtherNotesShow() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let ctx = container.mainContext
        let a = Note(title: "A"), b = Note(title: "B")
        ctx.insert(a); ctx.insert(b)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        let shared = try XCTUnwrap(NoteImageStore.add(imageData: png, to: a, in: ctx))
        let own = try XCTUnwrap(NoteImageStore.add(imageData: png, to: a, in: ctx))
        a.bodyMarkdown = NoteImageMarkup.line(shared) + "\n" + NoteImageMarkup.line(own)
        b.bodyMarkdown = "copied\n" + NoteImageMarkup.line(shared)
        try ctx.save()

        NoteImageStore.detachSharedImages(from: [a], context: ctx)
        ctx.delete(a)
        try ctx.save()

        let left = Set(try ctx.fetch(FetchDescriptor<Attachment>()).map(\.id))
        XCTAssertEqual(left, [shared.id])
    }
}
