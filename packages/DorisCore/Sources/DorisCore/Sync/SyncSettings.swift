import Foundation
import Combine

/// User-facing iCloud sync controls. Owns the persisted "should we use
/// CloudKit?", "should we auto-poke?", and the most recent successful
/// sync timestamp. UI binds to it; the runtime reads it to decide which
/// `ModelContainer` to construct, and whether to start the periodic timer.
///
/// Persisted in the **App Group** UserDefaults (`group.com.gavin.doris.shared`)
/// so the CLI, the share extension, and the main app see the same flags.
/// Falls back to `UserDefaults.standard` if the App Group isn't available
/// (unsigned dev builds — same fallback as IPCDirectory).
@MainActor
public final class SyncSettings: ObservableObject {
    public static let shared = SyncSettings()

    private static let cloudKitEnabledKey  = "doris.sync.cloudkit.enabled"
    private static let autoSyncEnabledKey  = "doris.sync.auto.enabled"
    private static let lastSyncedAtKey     = "doris.sync.lastSyncedAt"
    private static let lastSyncErrorKey    = "doris.sync.lastError"

    /// Cross-process defaults. Returns the App-Group-scoped suite when
    /// available, otherwise falls back to standard. Same fallback shape
    /// IPCDirectory uses for unsigned dev builds.
    private static let store: UserDefaults = {
        UserDefaults(suiteName: DorisIdentifiers.appGroup) ?? .standard
    }()

    /// True = ModelContainer is constructed with `cloudKitDatabase: .private(...)`.
    /// Flipping this requires an app restart for the change to take effect
    /// (SwiftData picks the configuration at container init time).
    @Published public var cloudKitEnabled: Bool {
        didSet { Self.store.set(cloudKitEnabled, forKey: Self.cloudKitEnabledKey) }
    }

    /// True = `SyncTimer` runs the periodic context.save() poke. Off = only
    /// manual `Sync Now` button + remote pushes update state.
    @Published public var autoSyncEnabled: Bool {
        didSet { Self.store.set(autoSyncEnabled, forKey: Self.autoSyncEnabledKey) }
    }

    /// Last error message from `SyncTimer.poke`, or nil if the most recent
    /// poke succeeded. UI surfaces this as a red indicator on the sync pill
    /// (iOS) or the Sync Now button (Mac). Cleared on next successful poke.
    @Published public var lastSyncError: String? {
        didSet {
            Self.store.set(lastSyncError, forKey: Self.lastSyncErrorKey)
        }
    }

    /// Last time `SyncTimer.poke` saved without error. Drives the "Last
    /// synced 30 s ago" label in Settings + the toolbar Sync Now button.
    @Published public var lastSyncedAt: Date? {
        didSet {
            if let d = lastSyncedAt {
                Self.store.set(d.timeIntervalSince1970, forKey: Self.lastSyncedAtKey)
            } else {
                Self.store.removeObject(forKey: Self.lastSyncedAtKey)
            }
        }
    }

    private init() {
        let store = Self.store
        // CloudKit defaults to ON.
        //
        // It used to default to OFF, opt-in-able only by setting a *shell*
        // environment variable (`DORIS_USE_CLOUDKIT=1`) — which cannot exist
        // for an app launched from the home screen or Finder. So a fresh
        // install had iCloud sync silently disabled with no in-app path to
        // discover why, on a product whose whole premise is a Mac and an
        // iPhone sharing one store.
        //
        // Defaulting ON is safe now: `DorisRuntime` gates the actual CloudKit
        // container on `CodeSigningCheck.hasTeamIdentifier`, so unsigned dev
        // builds still degrade to local-only instead of tripping SwiftData's
        // mirror crash. `DORIS_USE_CLOUDKIT=0` remains for forcing it off.
        //
        // Users who deliberately turned sync off are unaffected — the setter
        // persists the key, so an explicit `false` is read back below. Only
        // installs that never touched the toggle flip on.
        let ck = store.object(forKey: Self.cloudKitEnabledKey) as? Bool ?? true
        let auto = store.object(forKey: Self.autoSyncEnabledKey) as? Bool ?? true
        let last = store.object(forKey: Self.lastSyncedAtKey) as? TimeInterval
        let err = store.string(forKey: Self.lastSyncErrorKey)

        self.cloudKitEnabled = ck
        self.autoSyncEnabled = auto
        self.lastSyncedAt = last.map { Date(timeIntervalSince1970: $0) }
        self.lastSyncError = err

        // Env-var override for development, honored only while the user hasn't
        // made an explicit choice in Settings. Now that the default is ON, the
        // useful direction is "=0" (run a dev build against a purely local
        // store); "=1" is kept so existing shell setups keep working.
        if store.object(forKey: Self.cloudKitEnabledKey) == nil {
            switch ProcessInfo.processInfo.environment["DORIS_USE_CLOUDKIT"] {
            case "0": self.cloudKitEnabled = false
            case "1": self.cloudKitEnabled = true
            default:  break
            }
        }
    }

    /// True when the user asked for iCloud sync but the live container isn't
    /// actually mirroring — the state that used to be reported as a healthy
    /// "synced". Nil-safe: before the container is built we don't claim a
    /// mismatch.
    public var cloudKitDegraded: Bool {
        cloudKitEnabled && DorisRuntime.cloudKitActive == false
    }

    /// iOS: set false by the app delegate if APNs registration fails. Inbound
    /// CloudKit sync rides on those pushes, so a failure here means remote
    /// changes will never arrive — worth saying out loud rather than reporting
    /// a successful sync.
    @Published public var inboundPushReady: Bool = true

    /// Called by SyncTimer after a successful poke. Wraps in a MainActor
    /// hop to make Combine publishing safe.
    public func markSyncedNow() {
        lastSyncedAt = Date()
    }
}
