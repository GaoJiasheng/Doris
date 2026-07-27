import Foundation
import SwiftData
import DorisIPC

/// Single shared owner of the app's `ModelContainer`. Both the SwiftUI
/// `App` and the platform `AppDelegate` (NSApplicationDelegateAdaptor /
/// UIApplicationDelegateAdaptor) read from `DorisRuntime.shared.container`
/// so the main window, the menu-bar dropdown, the share extension's
/// in-process router, and any background services all share **one**
/// SwiftData backing store.
///
/// Why this exists: previously, DorisApp.swift and AppDelegate.swift each
/// called `ModelContainerFactory.make(...)` independently. In dev mode
/// (in-memory store) that meant the main window's notes and the dropdown
/// panel's notes were in two unrelated containers — edits in one never
/// surfaced in the other. Even on disk, two `NSPersistentCloudKitContainer`s
/// pointing at the same SQLite file is asking for corruption.
///
/// `DorisRuntime` is a `@MainActor` final class so accessing `.shared` from
/// SwiftUI views and AppDelegate hooks is safe. Container construction is
/// lazy on first read — it picks dev/in-memory vs CloudKit-backed based on
/// `SyncSettings.shared.cloudKitEnabled`.
@MainActor
public final class DorisRuntime {
    public static let shared = DorisRuntime()

    /// Whether the live container is ACTUALLY mirroring to CloudKit — as
    /// opposed to `SyncSettings.cloudKitEnabled`, which is only the user's
    /// intent. The two diverge whenever the fallback chain below degrades a
    /// requested CloudKit container to local-only, and every sync indicator
    /// used to read the intent, so a degraded container still displayed as
    /// "iCloud on / synced". Nil until the container is first built.
    public private(set) static var cloudKitActive: Bool?

    /// Lazily-built primary container. If construction fails (e.g. the user
    /// asked for CloudKit but isn't signed in), falls back through:
    ///   CloudKit  →  on-disk no-CloudKit  →  in-memory
    /// so the app still launches in some usable state.
    public lazy var container: ModelContainer = {
        let userWantsCloudKit = SyncSettings.shared.cloudKitEnabled

        // Defensive gate: SwiftData's CloudKit mirror traps the process
        // (brk 1 on `com.apple.coredata.cloudkit.queue`) when the binary
        // declares CloudKit entitlements but isn't actually signed for
        // them — typical for dev builds compiled with
        // `CODE_SIGN_IDENTITY=""`. The crash happens asynchronously, so
        // `try? ModelContainer(...)` can't catch it. We refuse to opt
        // into CloudKit when the signature isn't trustworthy, and write
        // the reason into `lastSyncError` so the UI banner / popover
        // can explain why "iCloud sync" doesn't actually sync.
        let canUseCloudKit = userWantsCloudKit && CodeSigningCheck.hasTeamIdentifier

        if userWantsCloudKit && !canUseCloudKit {
            let msg = "App is not signed with a Development Team — iCloud sync disabled to avoid a crash. Open the project in Xcode and Run with your signing team selected to enable sync."
            let zh = "App 没有用开发证书签名 — 为避免崩溃,iCloud 同步已自动禁用。请在 Xcode 中选择签名团队后 Run 即可启用同步。"
            let mode = UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh"
            SyncSettings.shared.lastSyncError = mode == "en" ? msg : zh
            DorisLog.sync.warning("DorisRuntime: CloudKit requested but binary has no team identifier; falling back to local-only")
        }

        if canUseCloudKit, let c = try? ModelContainerFactory.make(useCloudKit: true) {
            DorisLog.sync.info("DorisRuntime: CloudKit-backed container ready")
            Self.cloudKitActive = true
            return c
        }
        // CloudKit off (or failed). Try on-disk local persistence first so
        // notes survive app restarts even without iCloud.
        if let c = try? ModelContainerFactory.make(useCloudKit: false) {
            DorisLog.sync.info("DorisRuntime: local on-disk container (CloudKit off)")
            Self.cloudKitActive = false
            if userWantsCloudKit {
                // Requested but not delivered. Previously invisible: every
                // indicator read `cloudKitEnabled` (still true), so the app
                // claimed to be syncing while writing to a local-only store.
                DorisLog.sync.error("DorisRuntime: CloudKit was requested but the container fell back to LOCAL-ONLY")
            }
            return c
        }
        // Last resort — in-memory. Rare; usually means the App Group container
        // can't be reached and we have no place to put the SQLite file.
        if let c = try? ModelContainerFactory.make(inMemory: true) {
            DorisLog.sync.warning("DorisRuntime: in-memory fallback (data will not persist)")
            Self.cloudKitActive = false
            return c
        }
        // If even in-memory fails the app is unusable — but we can't return
        // nil from a lazy var, so trap. ModelContainer init only fails if
        // schema construction itself blows up, which would mean a code bug.
        fatalError("DorisRuntime: could not construct any ModelContainer")
    }()

    private init() {}
}
