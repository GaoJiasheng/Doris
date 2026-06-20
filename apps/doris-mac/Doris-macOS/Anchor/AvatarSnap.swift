import AppKit
import DorisIPC

/// Where a dragged avatar (edge logo or desktop pet) would land if released
/// right now: snapped to a screen edge (→ edge logo) or left free on the
/// desktop (→ pet). Drives both the dashed drop-preview and the commit.
enum AvatarSnapTarget: Equatable {
    case edge(AnchorEdge)
    case desktop
}

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
            let f = screen.frame
            let box = NSSize(width: 66, height: 46)
            switch edge {
            case .top:    return NSRect(x: f.midX - box.width / 2, y: f.maxY - box.height, width: box.width, height: box.height)
            case .bottom: return NSRect(x: f.midX - box.width / 2, y: f.minY,               width: box.width, height: box.height)
            case .left:   return NSRect(x: f.minX,                 y: f.midY - box.height / 2, width: box.width, height: box.height)
            case .right:  return NSRect(x: f.maxX - box.width,     y: f.midY - box.height / 2, width: box.width, height: box.height)
            }
        }
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
