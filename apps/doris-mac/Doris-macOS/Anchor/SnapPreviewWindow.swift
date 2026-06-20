import AppKit
import SwiftUI
import DorisUI

/// A borderless overlay that draws a dashed rounded-rect at the spot a
/// dragged avatar would land (edge logo or desktop pet). Shown live during a
/// drag, hidden on release. `ignoresMouseEvents` so it never intercepts the
/// drag itself.
@MainActor
final class SnapPreviewWindow {
    private var window: NSWindow?

    func show(frame: NSRect) {
        let win = window ?? makeWindow()
        window = win
        win.setFrame(frame, display: true)
        if !win.isVisible { win.orderFrontRegardless() }
    }

    func hide() { window?.orderOut(nil) }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        win.isReleasedWhenClosed = false
        // Above the pet / edge logo (both .statusBar) so the outline is
        // always visible, even when docking to the top over the menu bar.
        win.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true     // never steal the drag
        win.hidesOnDeactivate = false
        let host = NSHostingController(rootView: DashedDropPreview())
        host.view.wantsLayer = true
        win.contentViewController = host
        return win
    }
}

private struct DashedDropPreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CyberPalette.neonCyan.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        CyberPalette.neonCyan.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            )
            .padding(2)
    }
}
