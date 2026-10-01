import SwiftUI
import SwiftData
import ImageIO
import DorisCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NoteImageSize {
    @MainActor
    public var label: String {
        switch self {
        case .small:  return L("Small", "小")
        case .medium: return L("Medium", "中")
        case .large:  return L("Large", "大")
        case .full:   return L("Full width", "全宽")
        }
    }
}

/// Decodes body images from their `Attachment` bytes, downsampled to the
/// size they're drawn at, and caches them. Shared by the editors, the
/// checklist's image rows and the Markdown preview.
@MainActor
public final class NoteImageLoader {
    public static let shared = NoteImageLoader()

    private let cache = NSCache<NSString, HeroPlatformImage>()
    private let inlineCache = NSCache<NSString, HeroPlatformImage>()

    /// Height ÷ width for an image, from the stored pixel size — known
    /// before the bytes are, so layout doesn't jump when they arrive. 3:4
    /// when even that hasn't synced yet.
    public func aspect(_ id: UUID, in context: ModelContext) -> CGFloat {
        guard let a = NoteImageStore.attachment(id, in: context), a.pixelWidth > 0 else { return 0.75 }
        return CGFloat(a.pixelHeight) / CGFloat(a.pixelWidth)
    }

    /// The image at no more than `maxPixel` on its long side, or nil while
    /// its bytes haven't arrived (or it was deleted).
    public func image(_ id: UUID, maxPixel: CGFloat, in context: ModelContext) -> HeroPlatformImage? {
        // Bucket sizes so a resize doesn't re-decode for every point.
        let bucket = max(256, Int((maxPixel / 256).rounded(.up)) * 256)
        let key = "\(id.uuidString)-\(bucket)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = NoteImageStore.attachment(id, in: context)?.data,
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        #if os(macOS)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #else
        let image = UIImage(cgImage: cg)
        #endif
        cache.setObject(image, forKey: key)
        return image
    }

    /// The image drawn at exactly `size` points with rounded corners — what
    /// the text editors place inline, matching `NoteImageView`'s clip.
    public func inlineImage(_ id: UUID, size: CGSize, scale: CGFloat, in context: ModelContext) -> HeroPlatformImage? {
        let key = "\(id.uuidString)-\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
        if let hit = inlineCache.object(forKey: key) { return hit }
        guard let source = image(id, maxPixel: max(size.width, size.height) * scale, in: context) else { return nil }
        #if os(macOS)
        let rounded = NSImage(size: size, flipped: false) { r in
            NSBezierPath(roundedRect: r, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).addClip()
            source.draw(in: r)
            return true
        }
        #else
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let rounded = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: Self.cornerRadius).addClip()
            source.draw(in: rect)
        }
        #endif
        inlineCache.setObject(rounded, forKey: key)
        return rounded
    }

    static let cornerRadius: CGFloat = 6

    /// Full-resolution bytes, for "view full size".
    public func fullData(_ id: UUID, in context: ModelContext) -> Data? {
        NoteImageStore.attachment(id, in: context)?.data
    }

    /// A neutral card with a caption, drawn where an image's bytes haven't
    /// synced to this device yet — its text line can arrive first.
    public func placeholder(size: CGSize, text: String) -> HeroPlatformImage {
        let size = CGSize(width: max(size.width, 40), height: max(size.height, 30))
        #if os(macOS)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.secondaryLabelColor.withAlphaComponent(0.08).setFill(); path.fill()
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setStroke(); path.lineWidth = 1; path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                        .foregroundColor: NSColor.secondaryLabelColor]
            let s = text as NSString, ts = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2), withAttributes: attrs)
            return true
        }
        #else
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 8)
            UIColor.secondaryLabel.withAlphaComponent(0.08).setFill(); path.fill()
            UIColor.secondaryLabel.withAlphaComponent(0.25).setStroke(); path.lineWidth = 1; path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12),
                                                        .foregroundColor: UIColor.secondaryLabel]
            let s = text as NSString, ts = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2), withAttributes: attrs)
        }
        #endif
    }

    public static var syncingText: String { L("Image syncing…", "图片同步中…") }
}
