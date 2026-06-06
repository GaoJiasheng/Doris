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

        // Frame: restore the saved origin+size, or apply the default
        // size + a cascade origin for a fresh stick (a stored zero-size
        // frame counts as "fresh" → default size).
        if let saved = StickyStore.shared.frame(for: id),
           saved.size.width > 0, saved.size.height > 0 {
            panel.setFrame(saved, display: false)
        } else {
            panel.setContentSize(StickyStore.defaultSize)
            panel.center()
            let offset = CGFloat(windows.count) * 26
            var origin = panel.frame.origin
            origin.x += offset
            origin.y -= offset
            panel.setFrameOrigin(origin)
            StickyStore.shared.setFrame(id, panel.frame)
        }

        // Persist move + resize; clean the map if the window is closed
        // by any path other than our unstick().
        panel.onFrameChanged = { rect in StickyStore.shared.setFrame(id, rect) }
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
    /// Fired on move AND resize with the live window frame, so callers
    /// can persist origin + size together.
    var onFrameChanged: ((CGRect) -> Void)?
    var onClosed: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: StickyStore.defaultSize),
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
            self, selector: #selector(frameChanged),
            name: NSWindow.didMoveNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameChanged),
            name: NSWindow.didResizeNotification, object: self
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(willClose),
            name: NSWindow.willCloseNotification, object: self
        )
    }

    // Borderless panels default to non-key; sticky needs key status so
    // the title / checklist text fields are editable.
    override var canBecomeKey: Bool { true }

    @objc private func frameChanged() { onFrameChanged?(frame) }
    @objc private func willClose() { onClosed?() }
}
