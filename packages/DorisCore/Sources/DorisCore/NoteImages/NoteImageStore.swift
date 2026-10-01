import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftData
import DorisIPC

/// Turns pasted / dropped / picked image data into something fit to sync:
/// at most `maxPixel` on the long side, re-encoded, orientation baked in.
public enum NoteImageEncoder {
    /// Long-side cap. Sharp on a Retina screen at full note width, and keeps
    /// a typical photo or screenshot to a few hundred KB of iCloud.
    public static let maxPixel = 2048

    public struct Encoded: Sendable {
        public let data: Data
        public let width: Int
        public let height: Int
        public let mimeType: String
    }

    /// JPEG, unless the image has transparency (a PNG with alpha, a sticker):
    /// those stay PNG, since JPEG would turn the clear parts black.
    public static func encode(_ source: Data, maxPixel: Int = maxPixel, quality: Double = 0.82) -> Encoded? {
        guard let src = CGImageSourceCreateWithData(source as CFData, nil),
              CGImageSourceGetCount(src) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // apply EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }

        let hasAlpha = usesTransparency(image)
        let type: UTType = hasAlpha ? .png : .jpeg
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Encoded(data: out as Data, width: image.width, height: image.height,
                       mimeType: hasAlpha ? "image/png" : "image/jpeg")
    }

    /// Whether any pixel is actually see-through. Having an alpha channel
    /// isn't enough: screenshots copied to the clipboard carry one that is
    /// opaque everywhere, and keeping those as PNG makes them several times
    /// larger for nothing. Checked on a small rendition, which still shows
    /// any transparent area big enough to matter.
    static func usesTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let scale = min(1, 256 / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * scale)), h = max(1, Int(CGFloat(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = ctx.data else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 3, to: w * h * 4, by: 4) where bytes[i] < 255 { return true }
        return false
    }
}

/// Body images live in `Attachment` rows (bytes in `data`, synced as a
/// CloudKit asset) and are referenced from the note body by id — see
/// `NoteImageMarkup`.
@MainActor
public enum NoteImageStore {
    /// Encode `imageData`, store it for `note`, and return the reference to
    /// put in the body. Nil when the data isn't a readable image.
    public static func add(imageData: Data, to note: Note, in context: ModelContext,
                           size: NoteImageSize = .default) -> NoteImageRef? {
        guard let encoded = NoteImageEncoder.encode(imageData) else { return nil }
        let ext = encoded.mimeType == "image/png" ? "png" : "jpg"
        let attachment = Attachment(filename: "image.\(ext)", mimeType: encoded.mimeType,
                                    byteCount: encoded.data.count, relativePath: "", note: note)
        attachment.data = encoded.data
        attachment.pixelWidth = encoded.width
        attachment.pixelHeight = encoded.height
        context.insert(attachment)
        note.touch()
        try? context.save()
        return NoteImageRef(id: attachment.id, size: size)
    }

    public static func attachment(_ id: UUID, in context: ModelContext) -> Attachment? {
        var d = FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// How long an unreferenced image is kept before it's deleted. Generous
    /// on purpose: a note's text and its image sync separately, so an image
    /// can briefly exist on a device before the line that uses it; and a
    /// deleted image line can come back with undo.
    public static let orphanGracePeriod: TimeInterval = 7 * 24 * 60 * 60

    /// Delete body images no note references any more, once they're older
    /// than the grace period — otherwise every removed picture would sit in
    /// iCloud for good. A reference from *any* note counts, so a line copied
    /// into another note keeps its image alive.
    /// Before `notes` are deleted for good: their images cascade-delete with
    /// them, so detach any that another note's body still shows (an image
    /// copied from one note into another). The orphan sweep then keeps
    /// them for as long as something references them.
    public static func detachSharedImages(from notes: [Note], context: ModelContext) {
        let leaving = Set(notes.map(\.id))
        let owned = notes.flatMap { $0.attachments ?? [] }.filter { $0.pixelWidth > 0 }
        guard !owned.isEmpty else { return }
        var referenced = Set<UUID>()
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] where !leaving.contains(note.id) {
            for ref in NoteImageMarkup.refs(in: note.bodyMarkdown) { referenced.insert(ref.id) }
        }
        for a in owned where referenced.contains(a.id) { a.note = nil }
    }

    public static func purgeOrphans(context: ModelContext, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-orphanGracePeriod)
        let candidates = (try? context.fetch(FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.pixelWidth > 0 && $0.createdAt < cutoff }
        ))) ?? []
        guard !candidates.isEmpty else { return }
        let bodies = (try? context.fetch(FetchDescriptor<Note>()))?.map(\.bodyMarkdown) ?? []
        var referenced = Set<UUID>()
        for body in bodies {
            for ref in NoteImageMarkup.refs(in: body) { referenced.insert(ref.id) }
        }
        let orphans = candidates.filter { !referenced.contains($0.id) }
        guard !orphans.isEmpty else { return }
        orphans.forEach(context.delete)
        try? context.save()
        DorisLog.sync.debug("purged \(orphans.count) unreferenced note image(s)")
    }
}
