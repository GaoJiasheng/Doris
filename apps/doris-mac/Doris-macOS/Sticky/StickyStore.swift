import Foundation

/// Device-local record of which notes are stuck to the desktop and at
/// what position. Deliberately NOT a synced CloudKit field — "is this
/// note a desktop sticky on THIS Mac, and where" is inherently
/// per-device, so it lives in UserDefaults rather than on the Note.
@MainActor
final class StickyStore {
    static let shared = StickyStore()

    private static let key = "doris.sticky.notes"   // { uuidString: [x, y] }

    /// noteID → bottom-left origin in screen coordinates. `.zero` means
    /// "not positioned yet" — the window manager cascades a default.
    private(set) var positions: [UUID: CGPoint]

    private init() { positions = Self.load() }

    var stuckIDs: [UUID] { Array(positions.keys) }

    func isStuck(_ id: UUID) -> Bool { positions[id] != nil }

    func stick(_ id: UUID, at point: CGPoint = .zero) {
        guard positions[id] == nil else { return }
        positions[id] = point
        persist()
    }

    func unstick(_ id: UUID) {
        guard positions.removeValue(forKey: id) != nil else { return }
        persist()
    }

    func setPosition(_ id: UUID, _ point: CGPoint) {
        positions[id] = point
        persist()
    }

    private func persist() {
        var dict: [String: [Double]] = [:]
        for (id, p) in positions { dict[id.uuidString] = [Double(p.x), Double(p.y)] }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func load() -> [UUID: CGPoint] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return [:] }
        var result: [UUID: CGPoint] = [:]
        for (s, arr) in dict where arr.count == 2 {
            if let id = UUID(uuidString: s) {
                result[id] = CGPoint(x: arr[0], y: arr[1])
            }
        }
        return result
    }
}
