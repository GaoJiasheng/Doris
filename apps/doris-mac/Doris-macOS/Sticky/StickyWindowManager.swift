import AppKit
import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Owns the lifecycle of desktop sticky windows. One floating
/// `StickyPanel` per note in `StickyStore`. Observes the
/// `.dorisStickToDesktop` notification (posted by the shared context
/// menu) to add new stickies, and restores existing ones at launch.
@MainActor
final class StickyWindowManager: NSObject {
    static let shared = StickyWindowManager()

    private var windows: [UUID: StickyPanel] = [:]
    private var stickObserver: NSObjectProtocol?

    func start() {
        stickObserver = NotificationCenter.default.addObserver(
            forName: .dorisStickToDesktop, object: nil, queue: .main
        ) { note in
            guard let id = note.object as? UUID else { return }
            MainActor.assumeIsolated { StickyWindowManager.shared.stick(id) }
        }
        restore()
    }

    /// Recreate windows for every note still flagged as stuck.
    func restore() {
        for id in StickyStore.shared.stuckIDs { showWindow(for: id) }
    }

    func stick(_ id: UUID) {
        StickyStore.shared.stick(id)
        showWindow(for: id)
    }

    func unstick(_ id: UUID) {
        StickyStore.shared.unstick(id)
        if let panel = windows[id] {
            panel.onClosed = nil          // avoid the close hook re-entering
            panel.close()
        }
        windows[id] = nil
    }

    private func showWindow(for id: UUID) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let container = DorisRuntime.shared.container
        let ctx = container.mainContext
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        guard let note = try? ctx.fetch(descriptor).first else {
            StickyStore.shared.unstick(id)   // note no longer exists
            return
        }

        let root = StickyNoteView(note: note, onClose: { [weak self] in
            self?.unstick(id)
        })
        .modelContainer(container)

        let hosting = NSHostingController(rootView: root)
        let panel = StickyPanel(contentViewController: hosting)
        panel.noteID = id

        // Position: restore saved origin, or cascade a fresh one.
        let saved = StickyStore.shared.positions[id] ?? .zero
        if saved == .zero {
            panel.center()
            let offset = CGFloat(windows.count) * 26
            var origin = panel.frame.origin
            origin.x += offset
            origin.y -= offset
            panel.setFrameOrigin(origin)
            StickyStore.shared.setPosition(id, origin)
        } else {
            panel.setFrameOrigin(saved)
        }

        // Persist moves; clean the map if the window is closed by any
        // other path than our unstick().
        panel.onMoved = { origin in StickyStore.shared.setPosition(id, origin) }
        panel.onClosed = { [weak self] in
            StickyStore.shared.unstick(id)
            self?.windows[id] = nil
        }

        windows[id] = panel
        panel.orderFront(nil)
    }
}

/// Borderless floating panel hosting one sticky note. Movable by its
/// whole background; can become key so the inline text fields edit.
final class StickyPanel: NSPanel {
    var noteID: UUID?
    var onMoved: ((CGPoint) -> Void)?
    var onClosed: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 210),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Stay visible across Spaces, like the menu-bar anchor.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        minSize = NSSize(width: 180, height: 140)

        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove),
            name: NSWindow.didMoveNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(willClose),
            name: NSWindow.willCloseNotification, object: self
        )
    }

    // Borderless panels default to non-key; sticky needs key status so
    // the title / checklist text fields are editable.
    override var canBecomeKey: Bool { true }

    @objc private func didMove() { onMoved?(frame.origin) }
    @objc private func willClose() { onClosed?() }
}
