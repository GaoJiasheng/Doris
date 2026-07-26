import AppKit
import SwiftUI
import DorisUI

/// A small always-on-top "second logo": the focus countdown ring in a
/// notch-extension tab hugging the RIGHT of the camera cutout (flat left edge
/// into the notch, rounded bottom-right), symmetric to the avatar on the left.
///
/// **Real notches only.** Every other edge draws the ring INSIDE the avatar
/// window (`MenuBarModel.focusRing`) so the pair shares one panel, one
/// opacity, and one drag. Positioned by `AnchorController`; visible only
/// while a focus session is active.
@MainActor
final class FocusPipWindow {
    private let window: NSWindow
    var onClick: () -> Void = {}

    /// Overshoot (points the tab pokes into the notch), matched to the
    /// avatar's `NotchExtensionShape` so the mirror lines up.
    static let overshoot: CGFloat = 14

    init(onClick: @escaping () -> Void = {}) {
        self.onClick = onClick
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 50, height: 32)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        win.isReleasedWhenClosed = false
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.isMovable = false
        win.hidesOnDeactivate = false
        self.window = win

        let host = NSHostingController(rootView: FocusPipView(onClick: { [weak self] in self?.onClick() }))
        host.view.wantsLayer = true
        win.contentViewController = host

        // Hover tooltip — see `HoverTipWindow` for why AppKit's own tooltip
        // can't be used from a background agent.
        let tracker = HoverTrackingView(frame: host.view.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.tipProvider = { _ in FocusTimer.shared.session?.displayTitle }
        host.view.addSubview(tracker)
    }

    /// Set the tab's frame (called by the controller each time the avatar
    /// moves / a session starts).
    func update(frame: NSRect) {
        window.setFrame(frame, display: true)
    }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }
    var isVisible: Bool { window.isVisible }
}

private struct FocusPipView: View {
    let onClick: () -> Void

    var body: some View {
        ZStack {
            // Black tab mirroring the avatar's notch extension so the two
            // read as one pair bracketing the camera cutout.
            NotchExtensionShapeRight(cornerRadius: 10).fill(Color.black)
            // Shared badge — running ring / paused `II` / finished green
            // check, so the pip and the inline edge ring never drift apart.
            FocusRingBadge(diameter: 18, lineWidth: 2.5)
                // The overshoot pokes LEFT into the notch, so nudge the ring
                // into the visible RIGHT half (mirror of the avatar's nudge).
                .offset(x: FocusPipWindow.overshoot / 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { onClick() }
        // Right-click → duration / pause / stop, the same menu the inline
        // edge ring shows.
        .contextMenu { FocusRingActions() }
    }
}

/// Mirror of `NotchExtensionShape`: flat LEFT edge (poking into the notch from
/// the right), rounded bottom-RIGHT. Fuses with the RIGHT side of the notch.
struct NotchExtensionShapeRight: Shape {
    var cornerRadius: CGFloat = 10
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))                 // top-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))             // top-right
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))         // down the right edge
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),    // rounded bottom-right
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))             // along bottom (flat left, into notch)
        p.closeSubpath()                                               // up the left edge
        return p
    }
}
