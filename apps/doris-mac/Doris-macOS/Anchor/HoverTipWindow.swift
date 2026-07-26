import AppKit
import SwiftUI
import DorisUI

/// A tooltip that actually works for Doris's menu-bar windows.
///
/// `NSView.toolTip` (and SwiftUI's `.help`) never fires here: Doris is an
/// `LSUIElement` agent, its avatar/pip windows are borderless and never
/// become key, and AppKit's built-in tooltip machinery is gated on the
/// owning app being active. So we drive our own — an `.activeAlways`
/// tracking area (the one option that reports hover for a background app)
/// plus a tiny borderless window that draws the label.
@MainActor
final class HoverTipWindow {
    static let shared = HoverTipWindow()

    private let window: NSWindow
    private let model = HoverTipModel()
    /// Pending show, so a tip only appears after a deliberate hover rather
    /// than flashing as the pointer sweeps past on its way to the menu bar.
    private var pendingShow: DispatchWorkItem?
    private static let delay: TimeInterval = 0.45

    private init() {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 10, height: 10)),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        win.isReleasedWhenClosed = false
        // Above the avatar/pip (.statusBar) so it isn't drawn behind them.
        win.level = .init(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        // Never steal the hover we're reacting to.
        win.ignoresMouseEvents = true
        win.hidesOnDeactivate = false
        window = win

        let host = NSHostingController(rootView: HoverTipView(model: model))
        host.view.wantsLayer = true
        win.contentViewController = host
    }

    /// Show `text` anchored under `anchor` (a screen-coordinate rect — the
    /// hovered window's frame), after the hover delay.
    func schedule(text: String, under anchor: NSRect) {
        cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in self?.show(text: text, under: anchor) }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
    }

    func cancel() {
        pendingShow?.cancel()
        pendingShow = nil
        window.orderOut(nil)
    }

    private func show(text: String, under anchor: NSRect) {
        model.text = text
        // Measure the SwiftUI content so the window hugs the label.
        guard let host = window.contentViewController?.view else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let w = max(size.width, 40), h = max(size.height, 20)

        // Centered under the anchor, nudged back on-screen if it would spill
        // off either side or below the display.
        var x = anchor.midX - w / 2
        var y = anchor.minY - h - 6
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            x = min(max(x, f.minX + 4), f.maxX - w - 4)
            // No room below (bottom-edge dock) → flip above the anchor.
            if y < f.minY + 4 { y = anchor.maxY + 6 }
        }
        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        window.orderFrontRegardless()
    }
}

@MainActor
private final class HoverTipModel: ObservableObject {
    @Published var text: String = ""
}

private struct HoverTipView: View {
    @ObservedObject var model: HoverTipModel

    var body: some View {
        Text(model.text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 220)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

/// Transparent overlay that reports hover for a background agent's window.
///
/// `.activeAlways` is the load-bearing option — the default tracking modes
/// only report while the owning app is active, which Doris never is.
final class HoverTrackingView: NSView {
    /// Returns the tip text for the pointer's location in this view's
    /// coordinates, or nil for "no tip here" (e.g. over the cat, not the ring).
    var tipProvider: ((NSPoint) -> String?)?
    private var lastText: String?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    // Pass clicks/drags through to the SwiftUI content underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let text = tipProvider?(p)
        guard text != lastText else { return }   // don't restart the timer every pixel
        lastText = text
        if let text, let win = window {
            HoverTipWindow.shared.schedule(text: text, under: win.frame)
        } else {
            HoverTipWindow.shared.cancel()
        }
    }

    override func mouseExited(with event: NSEvent) {
        lastText = nil
        HoverTipWindow.shared.cancel()
    }
}
