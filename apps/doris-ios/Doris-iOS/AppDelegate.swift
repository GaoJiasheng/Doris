import UIKit
import WidgetKit
import SwiftData
import DorisCore
import DorisIPC
import DorisUI

/// iOS Doris is a **full read/write editor** sharing the same iCloud-mirrored
/// SwiftData store as macOS. Both platforms write through the same
/// `ModelContainerFactory`, the same `SchemaV2`, and the same CloudKit
/// private container (`iCloud.com.gavin.doris`).
///
/// Event-handling (silent pushes, BGTask refreshes, local notification
/// fan-out, IPC/router/outbox drainage) deliberately stays on macOS —
/// the Mac is the event hub. iOS relies on CloudKit's automatic mirror
/// sync + the 60-second `SyncTimer` poke. This means we do NOT wire:
///   · `UNUserNotificationCenter` authorization
///   · `application.registerForRemoteNotifications()`
///   · `BGTaskScheduler` background refresh
///   · `NotificationRouter` / `OutboxPublisher` / `SilentPushHandler`
///   · `CloudKitBootstrap.ensureZonesAndSubscriptions()`
///
/// If iOS ever needs to ingest events directly, those pieces wire back in.
@MainActor
final class DorisAppDelegate: NSObject, UIApplicationDelegate {
    private var syncTimer: SyncTimer?
    private var saveObserver: NSObjectProtocol?
    private var widgetReloadWork: DispatchWorkItem?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DueDateNotifier.requestAuthorization()
        // Match the home-screen icon to the selected character pack (no-op
        // for the default pack / when its alternate icon isn't bundled).
        AppIconManager.applyCurrent()
        observeSavesForWidgetReload()
        Task { @MainActor in
            // Single shared container — same one the SwiftUI scene sees,
            // configured with `.private(...)` CloudKit mirror inside
            // `ModelContainerFactory` when SyncSettings.cloudKitEnabled.
            let container = DorisRuntime.shared.container

            // SyncTimer's `poke` is just `context.save()` on the main
            // actor — flushes any local edits (toggling pin, marking a
            // checklist item done) so the CloudKit mirror picks them up.
            // The timer also drives the "Last synced 30 s ago" label in
            // Settings via `SyncSettings.markSyncedNow()`.
            self.syncTimer = SyncTimer(container: container, interval: 60)
            await self.syncTimer?.start()

            // Manual "Sync Now" hook used by the Settings button and
            // pull-to-refresh in NotesScreen.
            AppCommands.syncNow = { [weak self] in
                Task { @MainActor in
                    await self?.syncTimer?.pokeNow()
                }
            }
        }
        return true
    }

    /// Called every time the user brings the app to the foreground —
    /// switching back from Mac, after a long screen-off, etc. By the
    /// time they're looking at the app, the home-screen widget they
    /// just glanced at is already stale. Kick a fresh timeline reload
    /// so the widget catches up on whatever CloudKit pulled in while
    /// the app was suspended. Cheap; WidgetKit just enqueues a
    /// request and iOS schedules the actual refresh.
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Reflect anything CloudKit pulled in while we were suspended —
        // but only actually reload if the widget-visible data changed, so
        // we don't spend WidgetKit's reload budget on every app switch.
        WidgetReloadCoordinator.reloadIfChanged(container: DorisRuntime.shared.container)
    }

    /// Called as the app leaves the foreground — the user swiped to the
    /// home screen (very likely to glance at the widget), opened the app
    /// switcher, or locked the device. This is the moment the previous
    /// build missed: `didBecomeActive` only fires when they RETURN to the
    /// app, and the 60-second `SyncTimer` is suspended in the background,
    /// so an edit-then-leave left the widget stale until WidgetKit's
    /// ~hourly floor. Flush any pending in-app edits to the shared store
    /// FIRST (so the widget reads fresh rows), then ask WidgetKit to
    /// reload — by the time they're looking at the home screen the widget
    /// reflects what they just changed.
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Flush pending in-app edits to the shared store FIRST (so the
        // widget reads fresh rows), then reload — but only if the
        // widget-visible data actually changed since the last reload.
        let container = DorisRuntime.shared.container
        try? container.mainContext.save()
        WidgetReloadCoordinator.reloadIfChanged(container: container)
    }

    /// Front-load the widget reload to the moment data is saved.
    ///
    /// Previously the reload was only requested on the 60-second sync tick,
    /// on foreground, or at background-time. The last is the worst moment to
    /// ask: iOS is suspending the app and defers the reload, so an
    /// edit-then-leave only refreshed the widget "a while later". By
    /// observing `ModelContext.didSave` we register the reload **while the
    /// app is still foreground** — WidgetKit honors foreground-initiated
    /// requests far sooner, so by the time the user reaches the home screen
    /// the new timeline is usually already built.
    ///
    /// Debounced (0.4s) to coalesce edit bursts; `reloadIfChanged` no-ops
    /// when the widget-visible data didn't actually change, so this never
    /// wastes WidgetKit's reload budget.
    private func observeSavesForWidgetReload() {
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees the main thread → safe to hop to the
            // MainActor synchronously.
            MainActor.assumeIsolated { self?.scheduleWidgetReload() }
        }
    }

    private func scheduleWidgetReload() {
        widgetReloadWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                _ = WidgetReloadCoordinator.reloadIfChanged(container: DorisRuntime.shared.container)
            }
        }
        widgetReloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
