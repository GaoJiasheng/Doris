import AppKit
import SwiftUI
import DorisCore

/// Owns the single always-on-desktop dashboard panel. Reuses the
/// StickyPanel window chrome (borderless floating, movable, persists
/// origin). Visibility is driven by DesktopPanelSettings so it survives
/// relaunch.
@MainActor
final class DesktopPanelController {
    static let shared = DesktopPanelController()

    private var panel: StickyPanel?

    /// Called at launch — re-show if the user left it visible.
    func start() {
        if DesktopPanelSettings.shared.visible { show() }
    }

    func toggle() { panel == nil ? show() : hide() }

    func show() {
        DesktopPanelSettings.shared.visible = true
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let container = DorisRuntime.shared.container
        let root = DesktopPanelView(onClose: { [weak self] in self?.hide() })
            .modelContainer(container)
        let hosting = NSHostingController(rootView: root)
        let p = StickyPanel(contentViewController: hosting)
        p.setContentSize(NSSize(width: 290, height: 380))

        let saved = DesktopPanelSettings.shared.position
        if saved == .zero {
            // Park near the top-right of the main screen by default.
            if let screen = NSScreen.main {
                let vf = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: vf.maxX - 290 - 24, y: vf.maxY - 380 - 24))
            } else {
                p.center()
            }
            DesktopPanelSettings.shared.position = p.frame.origin
        } else {
            p.setFrameOrigin(saved)
        }

        p.onMoved = { origin in DesktopPanelSettings.shared.position = origin }
        p.onClosed = { [weak self] in
            DesktopPanelSettings.shared.visible = false
            self?.panel = nil
        }
        panel = p
        p.orderFront(nil)
    }

    func hide() {
        DesktopPanelSettings.shared.visible = false
        panel?.onClosed = nil
        panel?.close()
        panel = nil
    }
}
