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
    private static let opacityKey = "doris.desktopPanel.opacity"
    private static let onTopKey = "doris.desktopPanel.alwaysOnTop"

    /// Lowest opacity the slider allows — below this the panel is
    /// effectively invisible (and hard to reclaim), so we bottom out here.
    static let minOpacity: Double = 0.3

    @Published var visible: Bool {
        didSet { UserDefaults.standard.set(visible, forKey: Self.visibleKey) }
    }

    /// Panel *background* opacity — task text and the controls stay fully
    /// opaque so a see-through panel is still readable. 1.0 = solid,
    /// `minOpacity` = most transparent. The slider range enforces bounds.
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: Self.opacityKey) }
    }

    /// True → panel floats above other windows (`.floating`); false → it
    /// sits at normal window level and can be covered by active windows.
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Self.onTopKey) }
    }

    var position: CGPoint {
        didSet {
            UserDefaults.standard.set([Double(position.x), Double(position.y)], forKey: Self.posKey)
        }
    }

    private init() {
        visible = UserDefaults.standard.bool(forKey: Self.visibleKey)   // default false
        // `object(forKey:)` so an unset key falls back to the intended
        // default (1.0 / true) rather than UserDefaults' 0 / false.
        let storedOpacity = UserDefaults.standard.object(forKey: Self.opacityKey) as? Double
        opacity = storedOpacity.map { min(max($0, Self.minOpacity), 1.0) } ?? 1.0
        alwaysOnTop = (UserDefaults.standard.object(forKey: Self.onTopKey) as? Bool) ?? true
        if let arr = UserDefaults.standard.array(forKey: Self.posKey) as? [Double], arr.count == 2 {
            position = CGPoint(x: arr[0], y: arr[1])
        } else {
            position = .zero
        }
    }
}
