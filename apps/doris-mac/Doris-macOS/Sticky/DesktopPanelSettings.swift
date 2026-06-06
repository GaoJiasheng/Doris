import Foundation
import SwiftUI
import Combine

/// Device-local state for the desktop dashboard panel (pinned / today
/// at a glance). Like StickyStore, this is per-Mac (visibility +
/// on-screen position), so it lives in UserDefaults rather than a
/// synced field.
@MainActor
final class DesktopPanelSettings: ObservableObject {
    static let shared = DesktopPanelSettings()

    private static let visibleKey = "doris.desktopPanel.visible"
    private static let posKey = "doris.desktopPanel.origin"   // [x, y]

    @Published var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: Self.visibleKey) }
    }

    var position: CGPoint {
        didSet {
            UserDefaults.standard.set([Double(position.x), Double(position.y)], forKey: Self.posKey)
        }
    }

    private init() {
        visible = UserDefaults.standard.bool(forKey: Self.visibleKey)   // default false
        if let arr = UserDefaults.standard.array(forKey: Self.posKey) as? [Double], arr.count == 2 {
            position = CGPoint(x: arr[0], y: arr[1])
        } else {
            position = .zero
        }
    }
}
