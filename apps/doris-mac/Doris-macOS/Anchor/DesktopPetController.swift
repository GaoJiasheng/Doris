import AppKit
import SwiftUI
import DorisCore
import DorisUI

/// The free-floating animated desktop pet — the "detached" counterpart to
/// the edge-docked `MenuBarAvatarWindow`. A borderless, transparent,
/// always-on-top window that shows just the animated character (no card),
/// can be dragged anywhere, and remembers its position. Active only while
/// `AvatarSettings.placement == .desktop`; `AnchorController` owns the
/// instance and switches between this and the edge window.
///
/// Interactions: single-click → toggle the task dropdown (positioned next
/// to the pet); drag → move; right-click → options menu. The character
/// only emotes on events (gated by the activity level) — it never wanders.
@MainActor
final class DesktopPetController {
    private var window: NSWindow?
    private let onClick: () -> Void
    /// Cursor offset within the window when a drag began (global coords) —
    /// same absolute-repositioning trick the edge window uses to avoid the
    /// SwiftUI-translation feedback loop.
    private var dragCursorOffset: CGPoint?

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
    }

    var isVisible: Bool { window != nil }
    var frame: NSRect? { window?.frame }
    var screen: NSScreen? { window?.screen ?? NSScreen.main }

    func show() {
        if window == nil { build() }
        window?.orderFrontRegardless()
    }

    /// Tear the window down (not just orderOut) so the SwiftUI hosting view
    /// is released and the character animation stops consuming CPU while in
    /// edge mode / hidden.
    func hide() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        window = nil
        dragCursorOffset = nil
    }

    /// Rebuild at the current `petSize` (call when the size setting changes).
    func reloadSize() {
        guard isVisible else { return }
        hide()
        show()
    }

    private func build() {
        let w = AvatarSettings.shared.petSize.width
        let h = w * 1.5   // animation clip aspect ≈ 1:1.5

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: w, height: h)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        win.isReleasedWhenClosed = false
        win.level = .floating                       // above normal windows
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.isMovable = false                        // we drive drag manually
        win.hidesOnDeactivate = false

        let host = NSHostingController(rootView: DesktopPetContent(
            size: w,
            onClick: onClick,
            onDragChanged: { [weak self] t in self?.dragChanged(t) },
            onDragEnded:   { [weak self] in self?.dragEnded() }
        ))
        win.contentViewController = host
        win.setContentSize(NSSize(width: w, height: h))
        self.window = win
        positionInitially(win)
    }

    private func positionInitially(_ win: NSWindow) {
        let size = win.frame.size
        // Reuse the saved spot if it still lands on an attached screen.
        if let saved = AvatarSettings.shared.petPosition,
           NSScreen.screens.contains(where: { $0.frame.intersects(NSRect(origin: saved, size: size)) }) {
            win.setFrameOrigin(saved)
            return
        }
        // First run: park near the bottom-right of the main screen.
        if let vf = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: vf.maxX - size.width - 40, y: vf.minY + 80)
            win.setFrameOrigin(origin)
            AvatarSettings.shared.petPosition = origin
        }
    }

    // MARK: - Drag (free move, no edge snap)

    private func dragChanged(_ translation: CGSize) {
        guard let win = window else { return }
        let mouse = NSEvent.mouseLocation
        if dragCursorOffset == nil {
            dragCursorOffset = CGPoint(x: mouse.x - win.frame.origin.x,
                                       y: mouse.y - win.frame.origin.y)
        }
        guard let off = dragCursorOffset else { return }
        win.setFrameOrigin(CGPoint(x: mouse.x - off.x, y: mouse.y - off.y))
    }

    private func dragEnded() {
        dragCursorOffset = nil
        if let win = window { AvatarSettings.shared.petPosition = win.frame.origin }
    }
}

// MARK: - Pet content

private struct DesktopPetContent: View {
    let size: CGFloat
    let onClick: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        // Button = click; AvatarHero is non-interactive so the click/drag
        // belong to this wrapper, not the character's own tap reactions.
        Button(action: onClick) {
            AvatarHero(mood: .idle,
                       compact: true,
                       showWeather: false,
                       selfChrome: false,
                       transparentBackdrop: true,
                       interactive: false)
                .frame(width: size, height: size * 1.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(
            "Doris — drag to move · right-click for settings",
            "Doris — 拖动可移动 · 右键打开设置"
        ))
        // Identical to the edge avatar's right-click menu (MenuBarAvatarContent).
        .contextMenu {
            Button(L("Open Main Window", "打开主窗口")) {
                AppCommands.openMainWindow()
            }
            Divider()
            Button(L("Sync Now", "立即同步")) {
                AppCommands.syncNow()
            }
            Button(L("Settings…", "设置…")) {
                SettingsWindowController.shared.show()
            }
            Divider()
            Button(L("Quit Doris", "退出 Doris")) {
                NSApp.terminate(nil)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in onDragChanged(v.translation) }
                .onEnded { _ in onDragEnded() }
        )
    }
}
