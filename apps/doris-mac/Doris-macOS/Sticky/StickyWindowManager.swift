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

    /// When true (desktop panel, "always on top" OFF), a click "peeks" the
    /// panel above normal windows by raising it to `.floating`, and it
    /// recedes to `.normal` when the user next clicks outside it. A level-3
    /// window sits above every level-0 window regardless of which app is
    /// active, so no focus-stealing activation is needed. Left false for
    /// sticky notes and for the always-on-top case (permanently `.floating`).
    var raisesToFrontOnClick = false
    /// Global click monitor installed while a peeked panel is floated; a
    /// click anywhere OUTSIDE our windows recedes it. (Global monitors never
    /// see clicks inside our own windows, so reading/editing keeps it up.)
    private var peekClickMonitor: Any?

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

    // "Peek" a not-always-on-top panel above normal windows on click, then
    // recede when the user clicks elsewhere. `sendEvent` sees the click
    // before the content view consumes it (we don't swallow it, so the
    // button / field underneath still gets it).
    override func sendEvent(_ event: NSEvent) {
        if raisesToFrontOnClick, event.type == .leftMouseDown {
            peekToFront()
        }
        super.sendEvent(event)
    }

    /// Float the panel above all normal-level windows. Codex / Lark / WeChat
    /// are level-0 windows, so raising to level-3 `.floating` clears them
    /// purely by window level — no `NSApp.activate` (which, on a
    /// non-activating panel, bounced focus and dropped the panel right back).
    /// Then watch for a click elsewhere to recede.
    private func peekToFront() {
        level = .floating
        orderFrontRegardless()
        guard peekClickMonitor == nil else { return }
        peekClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.recedeFromPeek()
        }
    }

    /// Drop back to `.normal` once the user clicks outside the panel.
    private func recedeFromPeek() {
        if let m = peekClickMonitor { NSEvent.removeMonitor(m); peekClickMonitor = nil }
        if raisesToFrontOnClick { level = .normal }
    }

    /// Controller entry point for the "always on top" toggle. ON → permanent
    /// `.floating`; OFF → start at `.normal`, peeking on click. Either way,
    /// cancel any in-progress peek so a stale monitor can't fight the toggle.
    func applyAlwaysOnTop(_ on: Bool) {
        raisesToFrontOnClick = !on
        if let m = peekClickMonitor { NSEvent.removeMonitor(m); peekClickMonitor = nil }
        level = on ? .floating : .normal
    }

    @objc private func frameChanged() { onFrameChanged?(frame) }
    @objc private func willClose() { onClosed?() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let m = peekClickMonitor { NSEvent.removeMonitor(m) }
    }
}
