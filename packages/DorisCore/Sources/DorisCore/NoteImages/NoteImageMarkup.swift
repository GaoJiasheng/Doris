import Foundation

/// How wide an image sits in a note body, as a share of the text width.
/// Preset sizes rather than free resizing: the same four choices on Mac and
/// iPhone, one character in the markup, and no drag gesture fighting the
/// text view's scrolling and selection on a phone.
public enum NoteImageSize: String, CaseIterable, Sendable {
    case small = "s"
    case medium = "m"
    case large = "l"
    case full = "f"

    /// What a pasted image starts at. Half width keeps a tall phone
    /// screenshot from swallowing the note.
    public static let `default`: NoteImageSize = .medium

    public var widthFraction: Double {
        switch self {
        case .small:  return 1.0 / 3.0
        case .medium: return 0.5
        case .large:  return 0.75
        case .full:   return 1.0
        }
    }
}

/// One image in a note body: which attachment, and how wide.
public struct NoteImageRef: Hashable, Sendable {
    public var id: UUID
    public var size: NoteImageSize

    public init(id: UUID, size: NoteImageSize = .default) {
        self.id = id
        self.size = size
    }
}

/// The body stays plain Markdown. An image is a line of its own:
///
///     ![](doris-image:3F2A…-UUID?w=m)
///
/// Readable as Markdown anywhere (an image with an app-specific URL), and
/// the bytes live in the synced `Attachment` with that id. Images always
/// take a whole line — text above and below is the caption — which keeps
/// the editors' job to "this line is a picture" instead of rich text.
public enum NoteImageMarkup {
    public static let scheme = "doris-image"

    public static func line(_ ref: NoteImageRef) -> String {
        "![](\(scheme):\(ref.id.uuidString)?w=\(ref.size.rawValue))"
    }

    /// The image on this line, if the whole (trimmed) line is one. A missing
    /// or unknown size reads as the default, so hand-written lines work.
    public static func parse(line: some StringProtocol) -> NoteImageRef? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("!["), t.hasSuffix(")"),
              let open = t.range(of: "](\(scheme):") else { return nil }
        let inner = t[open.upperBound..<t.index(before: t.endIndex)]
        let parts = inner.split(separator: "?", maxSplits: 1)
        guard let idPart = parts.first, let id = UUID(uuidString: String(idPart)) else { return nil }
        var size = NoteImageSize.default
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, kv[0] == "w", let s = NoteImageSize(rawValue: String(kv[1])) { size = s }
            }
        }
        return NoteImageRef(id: id, size: size)
    }

    /// Every image a body references, in order.
    public static func refs(in body: String) -> [NoteImageRef] {
        guard body.contains(scheme) else { return [] }
        return body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { parse(line: $0) }
    }

    /// The body for places that show text, not pictures — list excerpts,
    /// sticky previews, notifications: each image line becomes
    /// `placeholder`.
    public static func displayText(_ body: String, placeholder: String) -> String {
        guard body.contains(scheme) else { return body }
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { parse(line: $0) == nil ? String($0) : placeholder }
            .joined(separator: "\n")
    }
}
