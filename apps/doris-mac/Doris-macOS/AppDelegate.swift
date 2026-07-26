import AppKit
import SwiftUI
import SwiftData
import Combine
import UserNotifications
import DorisCore
import DorisIPC
import DorisMacChrome
import DorisUI

@MainActor
final class DorisAppDelegate: NSObject, NSApplicationDelegate {
    private var anchorController: AnchorController?
    private var router: NotificationRouter?
    private var drainer: IPCRequestDrainer?
    private var fsEventReader: IPCFSEventReader?
    private var darwinKickSubscription: DarwinNotify.Subscription?
    private var syncTimer: SyncTimer?
    private var outboxPublisher: OutboxPublisher?
    private var silentPushHandler: SilentPushHandler?
    private var voiceController: VoiceController?
    /// App-wide local monitor for Cmd-+ / Cmd-− / Cmd-0. Lives here
    /// instead of on a specific window controller so the shortcut
    /// works in both the main window AND the dropdown popup — local
    /// monitors only fire when our app is active anyway, so we don't
    /// need a per-window gate (and the previous per-window gate is
    /// exactly what kept the popup from honoring the shortcut).
    private var zoomKeyMonitor: Any?
    /// Combine subscription: propagates AvatarSettings.activityLevel
    /// into HeroEvents so one-shot reactions respect the user's preference.
    private var activityLevelSink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched directly (not via launchd / `open`) the process is a background
        // process and SwiftUI windows don't show. Promote to accessory + show anchor.
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            try? IPCDirectory.ensureDirectories()
            let secret = try? KeychainSecretStore.ensureSecret()

            // Single shared container — DorisRuntime is the only place that
            // builds one. Anchor + main window + share extension all read
            // from `.shared.container` so edits in one surface in the other.
            let container = DorisRuntime.shared.container
            // `cloudKitOn` gates every CloudKit-touching subsystem
            // (OutboxPublisher, SilentPushHandler, CloudKitBootstrap).
            // We AND in the same code-signing check `DorisRuntime` uses
            // to gate the SwiftData container — instantiating
            // `CKContainer(identifier:)` on an unsigned dev build traps
            // the whole process, so all four paths must agree.
            let cloudKitOn = SyncSettings.shared.cloudKitEnabled
                && CodeSigningCheck.hasTeamIdentifier

            let router = NotificationRouter(modelContainer: container)
            self.router = router
            if cloudKitOn {
                self.outboxPublisher = OutboxPublisher()
                router.setOutbox(self.outboxPublisher)
            }

            _ = SettingsStore(container: container).load()
            // Anchor lives as an NSStatusItem in the menu bar (system handles placement
            // & cross-screen routing). Click → dropdown panel below it.
            let anchor = AnchorController(modelContainer: container)
            self.anchorController = anchor
            anchor.show()
            // No auto-expand at launch. The expanded surface is now the
            // unified main window (opened on demand from the notch/pet), and
            // auto-opening it briefly at every launch read as an unwanted
            // flash of the old dropdown. Doris starts idle in the menu bar /
            // as the desktop pet; the user clicks to open the window.

            // Route banner/fix through the anchor (replaces DynamicNotchKit).
            router.setPresenter(anchor)

            let drainer = IPCRequestDrainer(router: router, secret: secret)
            self.drainer = drainer
            await drainer.drain()

            self.fsEventReader = IPCFSEventReader { [weak drainer] in
                Task { @MainActor in await drainer?.drain() }
            }
            self.fsEventReader?.start()

            self.darwinKickSubscription = DarwinNotify.subscribe(DorisIdentifiers.darwinKickName) { [weak drainer] in
                Task { @MainActor in await drainer?.drain() }
            }

            if cloudKitOn {
                self.silentPushHandler = SilentPushHandler(router: router)
                NSApp.registerForRemoteNotifications()
            }

            self.syncTimer = SyncTimer(container: container, interval: 60)
            await self.syncTimer?.start()

            // Desktop sticky notes — observe "Stick to desktop" context-
            // menu requests and re-float any notes still stuck from a
            // previous session.
            StickyWindowManager.shared.start()
            // Desktop dashboard panel — re-show if left visible.
            DesktopPanelController.shared.start()

            // Token-usage monitor — watch ~/.claude & ~/.codex logs, backfill
            // history, and keep the dashboard fresh.
            TokenCollectionService.shared.start()

            // Match the Dock tile to the selected character pack (no-op for
            // the default pack, which uses the bundled icon).
            AppIconManager.applyCurrent()

            // Avatar's right-click menu calls into these hooks. Sync
            // completion fires a celebration so the cyber girl reacts.
            // Both manual buttons (toolbar + avatar menu) take this path.
            AppCommands.syncNow = { [weak self] in
                Task { @MainActor in
                    await self?.syncTimer?.pokeNow()
                    HeroEvents.shared.celebrate()
                }
            }
            // Manual `Open Main Window` path. The main window is now
            // built and shown by `MainWindowController` (no SwiftUI
            // `Window` scene anymore — that one auto-created itself
            // at launch / on activation despite all our suppressors).
            //
            // Two coupled behaviors: collapse the dropdown panel
            // (we don't want both surfaces visible at once) and open
            // the main window on the SAME display the dropdown was on
            // (multi-monitor users expect "open" to land where they
            // just clicked, not on whatever screen the window was last
            // closed on).
            AppCommands.openMainWindow = { [weak self] in
                let screen = self?.anchorController?.currentScreen
                self?.anchorController?.collapse()
                MainWindowController.shared.show(preferredScreen: screen)
            }

            // Settings — same panel the menu-bar avatar's right-click
            // "Settings…" opens. Routed through AppCommands so DorisUI
            // components (e.g. the sync popover's "Open Sync Settings"
            // button) can request the panel without taking a hard
            // dependency on the Mac app target.
            AppCommands.openSettings = {
                SettingsWindowController.shared.show()
            }

            // Focus (pomodoro) timer hooks — DorisUI owns the timer + UI, but
            // the banner (notch) and "完成" (SwiftData) live in the app target.
            FocusTimer.notify = { [weak self] session in
                self?.anchorController?.presentBanner(PresentableMessage(
                    id: UUID(),
                    title: session.isRest ? L("Break over", "休息结束") : L("Focus done", "专注结束"),
                    body: session.displayTitle,
                    source: .cliGeneric,
                    sourceAppId: nil,
                    iconName: "timer",
                    level: .reminder,
                    displayMode: .banner,
                    receivedAt: Date(),
                    clickAction: nil
                ))
            }
            FocusTimer.completeHandler = { session in
                FocusTaskCompleter.complete(session)
                HeroEvents.shared.celebrate(minActivity: 0)
            }

            // Voice capture: long-press the configured modifier → mic →
            // route to ChatGPT (or web fallback).
            self.voiceController = VoiceController()
            self.voiceController?.start()

            // Sync activity level preference → HeroEvents gate (0/1/2).
            // Also keep it live so toggling in Settings takes effect immediately.
            let applyActivity = {
                switch AvatarSettings.shared.activityLevel {
                case .quiet:    HeroEvents.shared.activityLevel = 0
                case .standard: HeroEvents.shared.activityLevel = 1
                case .lively:   HeroEvents.shared.activityLevel = 2
                }
            }
            applyActivity()
            self.activityLevelSink = AvatarSettings.shared.$activityLevel
                .receive(on: DispatchQueue.main)
                .sink { _ in applyActivity() }

            // Morning greeting — fire once per calendar day on first expand.
            DailyRitual.greetIfNewDay()

            // Request permission for local due-date reminders. Shows a
            // one-time system alert; subsequent calls are no-ops.
            DueDateNotifier.requestAuthorization()

            self.installZoomKeyMonitor()

            if cloudKitOn {
                Task.detached {
                    do {
                        try await CloudKitBootstrap.ensureZonesAndSubscriptions()
                    } catch {
                        DorisLog.sync.error("CloudKit bootstrap failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
    }

    /// Register a local NSEvent monitor for Cmd-+ / Cmd-− / Cmd-0.
    /// Local monitors only fire while one of *our* windows is the
    /// key window, which exactly matches "user wants to zoom Doris
    /// content" — no per-window gating needed.
    ///
    /// Matched by physical `keyCode` (not characters) because the
    /// latter goes through the active keyboard layout / input
    /// source. Under a Chinese IME or a remapper (Karabiner,
    /// Hammerspoon), the same physical key can return a swapped
    /// or substituted character. Physical keyCodes ignore that
    /// layer.
    ///
    /// Returning `nil` from the closure swallows the event so the
    /// system doesn't beep; returning the event passes it through.
    private func installZoomKeyMonitor() {
        guard zoomKeyMonitor == nil else { return }
        zoomKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            // US ANSI Mac keyCodes:
            //   24 = `=` / `+` (top row, right of `0`)
            //   27 = `-` / `_`
            //   29 = `0`
            //   69 / 78 / 82 = numpad +/−/0
            switch event.keyCode {
            case 24, 69:
                ZoomSettings.shared.zoomIn()
                return nil
            case 27, 78:
                ZoomSettings.shared.zoomOut()
                return nil
            case 29, 82:
                ZoomSettings.shared.reset()
                return nil
            case 13: // 'w' — Cmd-W closes the main window. It's borderless
                     // (no system close button), so AppKit would otherwise
                     // just beep. Only act when the main window is key; let
                     // other windows (e.g. Settings) handle their own Cmd-W.
                if NSApp.keyWindow?.identifier?.rawValue == "doris-main" {
                    Task { @MainActor in MainWindowController.shared.closeMainWindow() }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    /// Custom URL scheme handler — `doris://notify?...` enqueues a
    /// notification through the same IPC writer the CLI / AppleScript
    /// command use. Lets external automation (Shortcuts, shell `open`,
    /// browser bookmarklets) fire a Doris banner without needing TCC
    /// Automation permission (the way AppleScript would) or App Group
    /// write access (the way a non-signed CLI would). Query params:
    ///   - title (required)
    ///   - body
    ///   - source     — SourceKind rawValue, defaults to .cliGeneric
    ///   - level      — EventLevel rawValue, defaults to .info
    ///   - mode       — banner | fix, defaults to banner
    ///   - click      — URL string opened on click; can use any scheme
    ///
    /// Example:
    ///   open "doris://notify?title=Claude%20done&source=claudeCode&click=claude://"
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "notify":
                handleNotifyURL(url)
            default:
                // Other doris:// routes (note/<id>, intent/<name>, main,
                // new-note, sync) are handled by SwiftUI .onOpenURL
                // observers on the windows that care; nothing to do
                // at the app-delegate level.
                break
            }
        }
    }

    private func handleNotifyURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let q = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let v = item.value else { return nil }
            return (item.name, v)
        })
        guard let title = q["title"], !title.isEmpty else { return }

        let source = q["source"].flatMap { SourceKind(rawValue: $0) } ?? .cliGeneric
        let level  = q["level"].flatMap { EventLevel(rawValue: $0) } ?? .info
        let mode   = q["mode"].flatMap { DisplayMode(rawValue: $0) } ?? .banner
        let clickAction: ClickAction? = q["click"].flatMap { URL(string: $0) }.map { .openURL($0) }

        let payload = IPCNotifyPayload(
            title: title,
            body: q["body"],
            displayMode: mode,
            source: source,
            level: level,
            clickAction: clickAction
        )
        let request = IPCRequest(kind: .notify, payload: .notify(payload))
        try? IPCDirectory.ensureDirectories()
        do {
            try IPCWriter.enqueue(request)
            IPCWriter.kick()
        } catch {
            DorisLog.ipc.error("doris://notify enqueue failed: \(String(describing: error), privacy: .public)")
        }
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { @MainActor in
            await silentPushHandler?.handleRemoteNotification(userInfo)
        }
    }

    // MARK: - Suppress SwiftUI's "auto-open the main window" reflexes.
    //
    // Doris is a menu-bar agent. The dropdown panel is its primary UI.
    // SwiftUI / AppKit have several reflexes that try to be helpful by
    // popping the main window open at unwanted moments — we override them
    // all so the main window only ever appears via an explicit
    // `AppCommands.openMainWindow()` call (avatar right-click, or note
    // tap in the dropdown).

    /// Called once at launch, before SwiftUI processes its scenes. Returning
    /// `false` tells AppKit not to open an "untitled" document at start-up,
    /// which is the path SwiftUI uses to auto-instantiate the first window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Same plumbing but for the "click the app icon while no window is
    /// open" case. We have no Dock icon (LSUIElement: true) so this is
    /// rarely hit, but other AppKit paths (e.g. `NSApp.activate`) can
    /// still trip it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    /// State restoration ("Reopen windows when logging back in" + the
    /// per-app version of it) brings back whatever windows were open at
    /// last quit. For a menu-bar agent that means the main window pops
    /// up on every relaunch even though the user never asked for it.
    /// Always returning `false` keeps the launch experience clean: just
    /// the avatar + dropdown, nothing else.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }
}
