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
        let root = DesktopPanelView(
            onClose: { [weak self] in self?.hide() },
            onAlwaysOnTopChanged: { [weak self] on in
                self?.panel?.applyAlwaysOnTop(on)
            }
        )
        .modelContainer(container)
        let hosting = NSHostingController(rootView: root)
        let p = StickyPanel(contentViewController: hosting)
        p.setContentSize(NSSize(width: 290, height: 380))
        // Honor the saved always-on-top preference. StickyPanel defaults
        // to `.floating` (the alwaysOnTop == true case); drop to `.normal`
        // when the user turned it off so the panel can be covered.
        p.applyAlwaysOnTop(DesktopPanelSettings.shared.alwaysOnTop)

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

        p.onFrameChanged = { rect in DesktopPanelSettings.shared.position = rect.origin }
        p.onClosed = { [weak self] in
            // Only clear `panel` here. Do NOT persist visible=false: this
            // fires on app termination too (windows close on quit), which
            // would stop the panel from restoring on the next launch. The
            // explicit close (X button → hide()) owns the visible=false and
            // nils this handler before closing, so we never lose the panel
            // just because the app quit / was relaunched for an update.
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
