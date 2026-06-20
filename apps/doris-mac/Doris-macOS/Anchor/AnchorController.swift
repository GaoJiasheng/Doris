import AppKit
import SwiftUI
import SwiftData
import Combine
import DorisCore
import DorisIPC
import DorisMacChrome
import DorisUI

@MainActor
final class AnchorController: NSObject, NotificationPresenter, NSWindowDelegate {
    private let model = AnchorModel()
    private var panel: DorisAnchorPanel?
    private var avatarWindow: MenuBarAvatarWindow?
    /// Free-floating desktop pet — the detached counterpart to the edge
    /// avatar. Shown when `AvatarSettings.placement == .desktop`.
    private var desktopPet: DesktopPetController?
    /// Dashed drop-preview shown while dragging the logo / pet between
    /// edge-dock and free-desktop.
    private let snapPreview = SnapPreviewWindow()
    private var avatarSettingsSinks: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var bannerDismissTask: Task<Void, Never>?
    private let modelContainer: ModelContainer
    /// Global click monitor while the panel is expanded — fires for any
    /// mouse-down outside Doris's own windows, so we can collapse the
    /// panel popover-style. Nil when not expanded.
    private var outsideClickMonitor: Any?

    /// Expanded panel size when user clicks the anchor (no notification active).
    /// Wider than v0.1 to give the cyber-girl scene a proper hero column on the left.
    static let expandedWidth: CGFloat = 560
    static let expandedHeight: CGFloat = 380

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    func show() {
        if avatarWindow == nil {
            avatarWindow = MenuBarAvatarWindow(
                onClick: { [weak self] in self?.toggleExpanded() },
                onDragMove: { [weak self] center in self?.previewAvatarDrag(center: center) },
                onDragEnded: { [weak self] center in self?.commitEdgeDrag(center: center) ?? false }
            )
        }
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Hot-plug / lid-close fires this notification immediately,
                // but `NSScreen.auxiliaryTopLeftArea` and `safeAreaInsets`
                // are populated lazily by the window server — for a few
                // hundred ms after the notification they can still report
                // stale or zeroed geometry, which causes the notch-
                // extension math to land the avatar at the screen's far
                // left corner. Fire relayout at 0 / 300 / 1000 ms so the
                // late-arriving geometry gets a chance to be picked up.
                self?.scheduleAvatarRelayoutsAfterScreenChange()
            }
        }
        if desktopPet == nil {
            desktopPet = DesktopPetController(
                onClick: { [weak self] in self?.toggleExpanded() },
                onDragMove: { [weak self] center in self?.previewAvatarDrag(center: center) },
                onDragEnded: { [weak self] center in self?.commitPetDrag(center: center) ?? false }
            )
        }
        if avatarSettingsSinks.isEmpty {
            // Switch logo ↔ pet when the user changes placement; rebuild the
            // pet on size change. (avatarVisible is intentionally NOT observed
            // here — it only governs the in-window character, not the launcher.)
            AvatarSettings.shared.$placement
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applyPlacement() }
                .store(in: &avatarSettingsSinks)
            AvatarSettings.shared.$petSize
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.desktopPet?.reloadSize() }
                .store(in: &avatarSettingsSinks)
        }
        if panel == nil {
            buildPanel()
        }
        applyPlacement()
        // No zoom observer needed at the controller level. The panel
        // window's size is decoupled from zoom — Cmd-+ / Cmd-− only
        // changes font/icon scale (via `.dorisZoom()` inside the
        // SwiftUI tree); the panel window stays at whatever size the
        // user dragged it to (or the baseline).
    }

    // MARK: - NSWindowDelegate (resize)

    /// AppKit fires this when the user finishes dragging an edge of
    /// the panel to resize it. We:
    ///   1. Persist the new size as a *logical* size (divided by the
    ///      current zoom) so changing zoom afterwards still scales
    ///      the panel predictably.
    ///   2. Re-snap the panel back into its notch-anchored position
    ///      (`computeRect()`). Edge-dragging can move the panel off
    ///      the notch — dragging the bottom edge keeps the top
    ///      pinned, but dragging the left or right edge does not.
    ///      Recomputing pulls it back so the popup stays glued to
    ///      the menu bar with horizontal centering on the
    ///      (avatar + notch) span.
    nonisolated func windowDidEndLiveResize(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleResizeFinished()
        }
    }

    private func handleResizeFinished() {
        guard let panel else { return }
        // Save the panel's pixel dimensions directly — no zoom
        // division. The popup window size is decoupled from zoom;
        // Cmd-+ / Cmd-− only changes font/icon scale via
        // `.dorisZoom()` inside the SwiftUI tree.
        AnchorScreenStore.save(expandedSize: panel.frame.size)
        // Re-anchor to the notch with the new size baked in.
        let snapped = computeRect()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(snapped, display: true)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Three-shot relayout in response to a screen-parameters change.
    /// Fires now, again at 300 ms, and again at 1000 ms — covers the
    /// macOS window-server's lazy population of notch/auxiliary-area
    /// geometry after hot-plug. Each call is cheap (computes a frame,
    /// sets the window's origin/size); the redundancy is what makes
    /// the binding stable across plug-in / unplug events.
    private func scheduleAvatarRelayoutsAfterScreenChange() {
        avatarWindow?.relayout()
        for delayMs in [300, 1000] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                self?.avatarWindow?.relayout()
            }
        }
    }

    /// Screen the dropdown panel (or, if not visible, the menu-bar
    /// avatar) currently lives on. Used by the "open main window"
    /// command to land the main window on the same display the user
    /// just clicked from, instead of forcing it onto NSScreen.main.
    var currentScreen: NSScreen? {
        panel?.screen ?? avatarWindow?.screen
    }

    /// Collapse the expanded dropdown (no-op if already idle). Used as
    /// a precondition when opening the main window — the user shouldn't
    /// have two parallel surfaces visible for the same content.
    func collapse() {
        guard case .expanded = model.state else { return }
        model.state = .idle
        hidePanel()
    }

    /// Public entry for the launch path — open the dropdown panel at app
    /// start so the user immediately sees their inbox / notes / today
    /// instead of staring at an empty menu bar. Idempotent: a second call
    /// while already expanded does nothing (vs. `toggleExpanded` which
    /// would collapse it).
    func expand() {
        guard model.state != .expanded else { return }
        model.state = .expanded
        showPanel()
        HeroEvents.shared.greet()
    }

    // Auto-collapse used to fire 8 seconds after expand to keep idle CPU
    // down. With inline note editing in the dropdown that became
    // user-hostile — the panel would disappear out from under whatever
    // they were typing. We've since moved to "panel stays open until the
    // user clicks the avatar (or 'X') to close", and rely on the full
    // panel teardown on close (`tearDownPanelContent`) to flush all
    // SwiftUI animators when they're done.

    private func buildPanel() {
        let model = self.model
        let container = self.modelContainer
        // Banner click semantics:
        //   - If the message carries an explicit `clickAction` (e.g. the
        //     Claude Code / Codex / ChatGPT integrations always include
        //     `.openURL("claude://")` etc.), execute that action and
        //     dismiss the banner. The user lands straight in the source
        //     app, with Doris staying in its idle menu-bar state.
        //   - If there's no clickAction (CLI calls without `--click-url`,
        //     legacy events), keep the historical "dismiss banner + open
        //     the dropdown" behavior so the click isn't a dead-end.
        //
        // The avatar / logo idle-click path (handled separately, in
        // `onTapIdle`) keeps opening the dropdown — that's the user's
        // single explicit gesture to enter Doris itself.
        let onTapMessage: (AnchorMessage) -> Void = { [weak self] message in
            self?.dismissActiveMessage()
            if let action = message.clickAction {
                Task { @MainActor in ClickActionRouter.execute(action) }
            } else {
                self?.toggleExpanded()
            }
        }
        let onDismissMessage: (AnchorMessage) -> Void = { [weak self] _ in
            self?.dismissActiveMessage()
        }
        let onClose: () -> Void = { [weak self] in
            self?.dismissActiveMessage()
        }
        // Drag is no longer used (the status item lives where macOS puts it). We pass
        // no-op handlers to satisfy AnchorView's API.
        let noopDrag: (CGSize) -> Void = { _ in }
        let rootView = AnyView(
            AnchorView(
                model: model,
                position: .notchAdjacent,
                screenHasNotch: true,
                onTapIdle: { /* status item handles this */ },
                onTapMessage: onTapMessage,
                onDismissMessage: onDismissMessage,
                onCloseExpanded: onClose,
                onDragChanged: noopDrag,
                onDragEnded: noopDrag
            )
            .modelContainer(container)
        )

        if let existing = panel {
            // Reuse the existing NSPanel chrome and just remount the
            // SwiftUI host. We tear `contentViewController` down on hide
            // (so animations stop) and put a fresh one back here on next
            // show.
            existing.contentViewController = NSHostingController(rootView: rootView)
        } else {
            panel = AnchorPanelLayout.makeFloating(initialSize: NSSize(width: 1, height: 1)) {
                rootView
            }
            // Become the panel's window delegate so `windowDidEndLiveResize`
            // (fired when the user finishes dragging an edge to resize)
            // lands on `self.windowDidEndLiveResize(_:)` below, where we
            // persist the new size and re-snap the panel into its
            // notch-anchored position.
            panel?.delegate = self
        }
    }

    // MARK: - Expand / collapse

    private func toggleExpanded() {
        if case .expanded = model.state {
            model.state = .idle
            hidePanel()
        } else {
            model.state = .expanded
            showPanel()
            HeroEvents.shared.greet()
        }
    }

    private func dismissActiveMessage() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        model.state = .idle
        hidePanel()
    }

    private func showPanel() {
        // (Re)build the SwiftUI host so the AvatarHero / AnchorView tree
        // is freshly mounted. We tear it down on hide to stop animations,
        // so on show we have to put it back.
        if panel == nil || panel?.contentViewController == nil {
            buildPanel()
        }
        guard let panel else { return }
        let target = computeRect()

        // Pin the panel's NSAppearance to Doris's in-app theme so
        // any `Color(light:dark:)` lookups inside the SwiftUI tree
        // resolve against the SAME appearance the rest of the app
        // is using. Without this the panel inherits the system
        // appearance; if the system is in Auto / a different mode
        // than Doris's theme, the SwiftUI `.preferredColorScheme`
        // and the NSAppearance disagree, and dynamic NSColors
        // resolved during render can flicker between the two —
        // showing up as backdrop / text "changing color."
        panel.appearance = NSAppearance(
            named: ThemeSettings.shared.mode == .dark ? .darkAqua : .aqua
        )

        // Instant show — no frame grow, no alpha fade. Snap-on / snap-off
        // avoids any blend with the menu bar / desktop behind it.
        panel.setFrame(target, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // Outside-click auto-dismiss is a popover affordance — only
        // attach it for the expanded panel. Banners auto-dismiss on a
        // timer and fix messages have their own X / tap-to-act paths.
        if case .expanded = model.state {
            installOutsideClickMonitor()
        }
    }

    /// Install a global mouse-down monitor that collapses the panel on
    /// any click outside Doris's own windows. Replaces the dedicated X
    /// close button — the panel now behaves like a popover (clicking
    /// the desktop, another app, or the menu bar dismisses it).
    /// Idempotent — uninstalls any prior monitor first.
    private func installOutsideClickMonitor() {
        if let existing = outsideClickMonitor {
            NSEvent.removeMonitor(existing)
            outsideClickMonitor = nil
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // Global monitors only fire for events outside our own
            // windows, so reaching here already means "click landed
            // somewhere else." Collapse the panel.
            Task { @MainActor [weak self] in
                self?.dismissActiveMessage()
            }
        }
    }

    private func uninstallOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func hidePanel() {
        uninstallOutsideClickMonitor()
        guard let panel else {
            tearDownPanelContent()
            return
        }
        // Instant hide — matches the snap-on `showPanel`. Earlier
        // we animated alpha 1 → 0 over 0.18s, but during the fade
        // the half-opaque card mixed with the menu bar / desktop
        // colors behind it and read as the backdrop / text shifting.
        // Snap-off avoids the blend.
        //
        // `tearDownPanelContent` still releases the SwiftUI host so
        // any internal `TimelineView` / Canvas inside the dropped
        // view tree stops burning CPU — that's the real reason hide
        // is split into "ordered-out + content-torn-down" rather
        // than just `orderOut(nil)`.
        panel.orderOut(nil)
        tearDownPanelContent()
    }

    private func tearDownPanelContent() {
        // Setting `contentViewController = nil` alone doesn't fully tear
        // down SwiftUI's hosting tree — the GraphHost / animator state
        // can outlive the controller, keeping CPU spinning even after
        // the window is `orderOut`'d. Releasing the entire NSPanel is
        // the only reliable way to flush every animator. `buildPanel()`
        // recreates a fresh one on the next `showPanel()` call.
        panel?.close()
        panel?.contentViewController = nil
        panel = nil
    }

    /// A 2-point rect at the bottom-center of the avatar — the panel scales out from
    /// here on show, and back into here on hide.
    private func collapsedRect() -> NSRect {
        if let avatar = avatarWindow {
            let f = avatar.screenFrame
            return NSRect(x: f.midX - 1, y: f.minY - 1, width: 2, height: 2)
        }
        // Avoid `NSScreen.screens.first!` — the force-unwrap embeds the
        // source file path into the runtime trap message, leaking the
        // build-tree path into the .dylib's `__cstring` section. The
        // `guard let` form has the same behavior in practice (we only
        // reach this branch when there's no avatar window, which itself
        // requires a screen) but doesn't bake any path metadata.
        guard let s = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first else {
            return .zero
        }
        return NSRect(x: s.frame.maxX - 16, y: s.frame.maxY - 16, width: 2, height: 2)
    }

    // MARK: - Frame placement

    private func applyFrame(animated: Bool) {
        guard let panel = panel else { return }
        let rect = computeRect()
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.92, 0.34, 1.04)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(rect, display: true)
            })
        } else {
            panel.setFrame(rect, display: true)
        }
    }

    /// Compute the panel rect anchored to the avatar window. The panel grows AWAY from
    /// the screen edge: down for top, up for bottom, left for right edge, right for left.
    /// Show the edge avatar or the desktop pet per the current settings.
    /// The edge `avatarWindow` always exists (it anchors banners + provides
    /// the notch layout), but is hidden while the pet is active.
    private func applyPlacement() {
        // The menu-bar avatar (notch logo OR desktop pet) is the app's
        // anchor / launcher — ALWAYS exactly one of the two, chosen by
        // `placement`. It is deliberately NOT tied to `avatarVisible`:
        // that toggle only governs the in-window animated character
        // (main-window left column + dropdown hero). Tying the launcher to
        // it left the user with no way to open the app when they hid the
        // character.
        switch AvatarSettings.shared.placement {
        case .desktop:
            avatarWindow?.hide()
            desktopPet?.show()
        case .edge:
            desktopPet?.hide()
            avatarWindow?.show()
        }
    }

    // MARK: - Drag dock / detach (logo ↔ desktop pet)

    /// Live during a drag of either the edge logo or the pet: show the dashed
    /// drop-preview where it would land if released now.
    private func previewAvatarDrag(center: CGPoint) {
        guard let screen = AvatarSnap.screen(containing: center) else { snapPreview.hide(); return }
        let target = AvatarSnap.evaluate(center: center, screen: screen)
        let w = AvatarSettings.shared.petSize.width
        let frame = AvatarSnap.previewFrame(for: target, center: center, screen: screen,
                                            petSize: CGSize(width: w, height: w * 1.5))
        snapPreview.show(frame: frame)
    }

    /// Edge logo released at `center`. Returns true if it detached to the
    /// desktop (placement switched to pet); false → the edge window snaps to
    /// the nearest edge itself.
    private func commitEdgeDrag(center: CGPoint) -> Bool {
        snapPreview.hide()
        guard let screen = AvatarSnap.screen(containing: center) else { return false }
        if case .desktop = AvatarSnap.evaluate(center: center, screen: screen) {
            let w = AvatarSettings.shared.petSize.width
            AvatarSettings.shared.petPosition = CGPoint(x: center.x - w / 2, y: center.y - (w * 1.5) / 2)
            AvatarSettings.shared.placement = .desktop   // → applyPlacement shows the pet
            return true
        }
        return false
    }

    /// Pet released at `center`. Returns true if it docked to an edge
    /// (placement switched to edge); false → it stays a free pet.
    private func commitPetDrag(center: CGPoint) -> Bool {
        snapPreview.hide()
        guard let screen = AvatarSnap.screen(containing: center) else { return false }
        if case .edge(let edge) = AvatarSnap.evaluate(center: center, screen: screen) {
            AnchorScreenStore.save(screen: screen)
            AnchorScreenStore.save(edge: edge)
            AvatarSettings.shared.placement = .edge      // → applyPlacement shows the edge logo
            return true
        }
        return false
    }

    /// Panel rect when the avatar is a free desktop pet: centered on the pet,
    /// below it (or above if there's no room), clamped to the screen.
    private func petAnchoredRect(petFrame: NSRect, size: CGSize, screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        var x = petFrame.midX - size.width / 2
        var y = petFrame.minY - 6 - size.height          // below the pet
        if y < vf.minY + 8 { y = petFrame.maxY + 6 }      // flip above
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func computeRect() -> NSRect {
        let (width, height): (CGFloat, CGFloat)
        switch model.state {
        case .idle:
            return .zero
        case .banner:
            width = AnchorPanelLayout.bannerWidth
            height = AnchorPanelLayout.bannerHeight
        case .fix:
            width = AnchorPanelLayout.fixWidth
            height = AnchorPanelLayout.fixHeight
        case .expanded:
            // Saved size wins if the user has manually resized — kept
            // in raw pixels (no zoom multiplication). Zoom affects
            // font / icon scale inside the panel via `.dorisZoom()`,
            // NOT the panel window's outer dimensions. Drag the
            // border to resize the window; press Cmd-+ to scale
            // content within whatever size you chose.
            let saved = AnchorScreenStore.savedExpandedSize()
                ?? CGSize(width: Self.expandedWidth, height: Self.expandedHeight)
            width = saved.width
            height = saved.height
        }

        // Desktop-pet mode: anchor only the EXPANDED dropdown next to the pet
        // (click-me → menu beside me). Banners / fix notifications stay at the
        // notch / top of the display — they shouldn't chase the pet around.
        if model.state == .expanded,
           AvatarSettings.shared.placement == .desktop,
           let petFrame = desktopPet?.frame,
           let petScreen = desktopPet?.screen {
            return petAnchoredRect(petFrame: petFrame,
                                   size: CGSize(width: width, height: height),
                                   screen: petScreen)
        }

        if let avatar = avatarWindow, let screen = avatar.screen {
            let aFrame = avatar.screenFrame
            let s = screen.frame
            // Zero-gap on the `.top` edge so the dropdown's flat top
            // edge sits flush against the bottom of the avatar / menu
            // bar — gives the "growing out of the notch" illusion. Side
            // edges still use a small visual gap because there's no
            // notch-merge story there.
            let gap: CGFloat = (avatar.edge == .top) ? 0 : 6

            // The panel anchors to the screen edge the avatar lives on, but the
            // horizontal centering rule differs for the `.top` edge: on a notched
            // display where the avatar parks beside the notch, "screen-centered"
            // looks visually off because the (avatar + notch) span is not centered
            // on the screen — the avatar is to the left of center. Centering the
            // panel under the visual group (avatar's outer edge → notch's far
            // edge) makes the dropdown read as belonging to the logo.
            switch avatar.edge {
            case .top:
                let panelX: CGFloat
                if #available(macOS 12.0, *),
                   screen.safeAreaInsets.top > 0,
                   let leftArea = screen.auxiliaryTopLeftArea,
                   let rightArea = screen.auxiliaryTopRightArea {
                    // Combined span = from whichever of (avatar.minX, leftArea.maxX)
                    // is further left, to whichever of (avatar.maxX, rightArea.minX)
                    // is further right. Currently the avatar parks left of the
                    // notch so `combinedLeft = aFrame.minX` and `combinedRight =
                    // rightArea.minX` (the notch's right edge); but doing it via
                    // min/max keeps the math correct if the avatar ever lands
                    // right of the notch.
                    _ = leftArea  // referenced for symmetry / future right-of-notch case
                    let combinedLeft = min(aFrame.minX, leftArea.maxX)
                    let combinedRight = max(aFrame.maxX, rightArea.minX)
                    let combinedMid = (combinedLeft + combinedRight) / 2
                    // Clamp so the panel never overflows the screen with a small
                    // visual inset on whichever side it bumps into.
                    let inset: CGFloat = 6
                    let unclamped = combinedMid - width / 2
                    panelX = min(max(unclamped, s.minX + inset), s.maxX - width - inset)
                } else {
                    // No notch — fall back to screen-centered, which matches the
                    // fake-notch idle placement at midX.
                    panelX = s.midX - width / 2
                }
                let y = aFrame.minY - gap - height
                return NSRect(x: panelX, y: y, width: width, height: height)
            case .bottom:
                // Grow upward from the screen's bottom edge, horizontally centered.
                let x = s.midX - width / 2
                let y = aFrame.maxY + gap
                return NSRect(x: x, y: y, width: width, height: height)
            case .right:
                // Grow leftward from the right edge, vertically centered.
                let x = aFrame.minX - gap - width
                let y = s.midY - height / 2
                return NSRect(x: x, y: y, width: width, height: height)
            case .left:
                // Grow rightward from the left edge, vertically centered.
                let x = aFrame.maxX + gap
                let y = s.midY - height / 2
                return NSRect(x: x, y: y, width: width, height: height)
            }
        }

        // Fallback: top-right of the primary screen. (See `collapsedRect`
        // for why we don't `force-unwrap NSScreen.screens.first` here —
        // the trap message would leak the source path.)
        guard let s = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first else {
            return .zero
        }
        let pad: CGFloat = 6
        return NSRect(
            x: s.frame.maxX - width - pad,
            y: s.frame.maxY - height - 32,
            width: width,
            height: height
        )
    }

    // MARK: - NotificationPresenter

    nonisolated func presentBanner(_ message: PresentableMessage) {
        let m = AnchorMessage(
            id: message.id,
            title: message.title,
            body: message.body,
            iconName: message.iconName ?? message.source.sfSymbol,
            source: message.source,
            level: message.level,
            displayMode: .banner,
            receivedAt: message.receivedAt,
            clickAction: message.clickAction
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.model.flashNotifyReaction()
            HeroEvents.shared.alert()
            self.model.state = .banner(message: m)
            self.showPanel()
            self.bannerDismissTask?.cancel()
            // Level-driven duration (info 1.5s, reminder 4s) plus a
            // +2s bump for agent-completion sources (Claude Code /
            // Codex) so their banner is easier to catch — see
            // AnchorMessage.bannerDuration. Critical would be .infinity
            // but routes through `presentFix` and never reaches here.
            let duration = m.bannerDuration
            self.bannerDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if case .banner(let current) = self?.model.state, current.id == m.id {
                    self?.dismissActiveMessage()
                }
            }
        }
    }

    nonisolated func presentFix(_ message: PresentableMessage) {
        let m = AnchorMessage(
            id: message.id,
            title: message.title,
            body: message.body,
            iconName: message.iconName ?? message.source.sfSymbol,
            source: message.source,
            level: message.level,
            displayMode: .fix,
            receivedAt: message.receivedAt,
            clickAction: message.clickAction
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.bannerDismissTask?.cancel()
            self.bannerDismissTask = nil
            self.model.flashNotifyReaction()
            HeroEvents.shared.alert()
            self.model.state = .fix(message: m)
            self.showPanel()
        }
    }

    nonisolated func dismiss(messageID: UUID) {
        Task { @MainActor [weak self] in
            self?.dismissActiveMessage()
        }
    }
}
