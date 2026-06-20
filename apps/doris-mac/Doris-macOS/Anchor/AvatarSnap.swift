import AppKit
import DorisIPC

/// Where a dragged avatar (edge logo or desktop pet) would land if released
/// right now: snapped to a screen edge (→ edge logo) or left free on the
/// desktop (→ pet). Drives both the dashed drop-preview and the commit.
enum AvatarSnapTarget: Equatable {
    case edge(AnchorEdge)
    case desktop
}

@MainActor
enum AvatarSnap {
    /// How close (pts) the dragged window's center must be to a screen edge
    /// to count as "docking" there.
    static let dockDistance: CGFloat = 110
    /// Dock only when also within this fraction of the edge's center (so
    /// dragging into a corner doesn't accidentally dock).
    static let centerFraction: CGFloat = 0.34

    static func evaluate(center: CGPoint, screen: NSScreen) -> AvatarSnapTarget {
        let f = screen.frame
        let nearMidX = abs(center.x - f.midX) <= f.width  * centerFraction
        let nearMidY = abs(center.y - f.midY) <= f.height * centerFraction
        if (f.maxY - center.y) <= dockDistance, nearMidX { return .edge(.top) }
        if (center.y - f.minY) <= dockDistance, nearMidX { return .edge(.bottom) }
        if (center.x - f.minX) <= dockDistance, nearMidY { return .edge(.left) }
        if (f.maxX - center.x) <= dockDistance, nearMidY { return .edge(.right) }
        return .desktop
    }

    /// The frame to draw the dashed drop-preview at for a given target.
    /// - desktop: a pet-sized box centered on the cursor (where the pet lands).
    /// - edge: a small logo-sized box flush against that edge's center.
    static func previewFrame(for target: AvatarSnapTarget,
                             center: CGPoint,
                             screen: NSScreen,
                             petSize: CGSize) -> NSRect {
        switch target {
        case .desktop:
            return NSRect(x: center.x - petSize.width / 2,
                          y: center.y - petSize.height / 2,
                          width: petSize.width, height: petSize.height)
        case .edge(let edge):
            // Use the REAL docked-logo frame so the dashed outline matches
            // where/what it'll actually become (notch-extension at top, etc.).
            return MenuBarAvatarWindow.logoFrame(edge: edge, on: screen)
        }
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
