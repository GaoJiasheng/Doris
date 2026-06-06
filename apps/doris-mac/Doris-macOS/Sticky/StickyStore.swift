import Foundation
import CoreGraphics

/// Device-local record of which notes are stuck to the desktop and the
/// frame (origin + size) of each sticky window. Deliberately NOT a
/// synced CloudKit field — "is this note a desktop sticky on THIS Mac,
/// where, and how big" is inherently per-device, so it lives in
/// UserDefaults rather than on the Note.
///
/// A stored frame of `.zero` (or zero size) means "stuck but not sized
/// yet" → the window manager applies the default size + a cascade
/// origin. Unsticking removes the entry entirely, so re-sticking later
/// starts fresh at the default size again.
@MainActor
final class StickyStore {
    static let shared = StickyStore()

    /// Comfortable default — the old 230×210 was too cramped to read a
    /// title + body. Used whenever a note is freshly stuck.
    static let defaultSize = CGSize(width: 300, height: 300)

    private static let key = "doris.sticky.notes"   // { uuidString: [x, y, w, h] }

    private(set) var frames: [UUID: CGRect]

    private init() { frames = Self.load() }

    var stuckIDs: [UUID] { Array(frames.keys) }

    func isStuck(_ id: UUID) -> Bool { frames[id] != nil }

    func frame(for id: UUID) -> CGRect? { frames[id] }

    /// Mark stuck without a frame yet (manager fills in default + cascade).
    func stick(_ id: UUID) {
        guard frames[id] == nil else { return }
        frames[id] = .zero
        persist()
    }

    func unstick(_ id: UUID) {
        guard frames.removeValue(forKey: id) != nil else { return }
        persist()
    }

    /// Persist the live window frame (called on move + resize).
    func setFrame(_ id: UUID, _ rect: CGRect) {
        frames[id] = rect
        persist()
    }

    private func persist() {
        var dict: [String: [Double]] = [:]
        for (id, r) in frames {
            dict[id.uuidString] = [Double(r.origin.x), Double(r.origin.y),
                                   Double(r.size.width), Double(r.size.height)]
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func load() -> [UUID: CGRect] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        var result: [UUID: CGRect] = [:]
        for (s, arr) in dict {
            guard let id = UUID(uuidString: s) else { continue }
            if arr.count == 4 {
                result[id] = CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
            } else if arr.count == 2 {
                // Migrate older position-only entries (size → default).
                result[id] = CGRect(origin: CGPoint(x: arr[0], y: arr[1]), size: .zero)
            }
        }
        return result
    }
}
