import Foundation
import DorisIPC
import SwiftData
import CloudKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Periodically calls `ModelContext.save()` to flush pending writes and let
/// SwiftData's CloudKit mirror push them upstream — then verifies CloudKit
/// is actually reachable before declaring success. Local `context.save()`
/// only writes to the SQLite store; SwiftData's CloudKit mirror is
/// asynchronous and ignorant of failures (no Apple ID, no network, account
/// restricted). Earlier the "Sync Now" button cheerfully reported success
/// in any of those cases. Now we do a real `CKContainer.accountStatus()`
/// plus a `userRecordID()` roundtrip after the local save; only if that
/// roundtrip succeeds do we stamp `lastSyncedAt`.
///
/// On failure, `SyncSettings.shared.lastSyncError` carries a human-readable
/// reason (e.g. "未登录 iCloud 账号" / "No iCloud account signed in") so
/// both iOS and Mac sync UIs can surface a red alert without digging into
/// logs. `lastSyncedAt` is NOT updated on failure — the "Last synced N
/// minutes ago" label stays anchored to the last verified-good sync.
///
/// Also runs a 30-day tombstone purge on each poke: notes that have been
/// soft-deleted (`archived = true`) for 30+ days are hard-deleted so they
/// don't accumulate indefinitely in iCloud.
public actor SyncTimer {
    private let container: ModelContainer
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    public init(container: ModelContainer, interval: TimeInterval = 60) {
        self.container = container
        self.interval = interval
    }

    public func start() async {
        guard task == nil else { return }
        let auto = await MainActor.run { SyncSettings.shared.autoSyncEnabled }
        guard auto else {
            DorisLog.sync.debug("auto-sync disabled by user; timer not started")
            return
        }
        let interval = self.interval
        let containerRef = container
        task = Task.detached { [weak self] in
            while let self, !Task.isCancelled {
                await self.poke(container: containerRef)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Explicit user-driven sync. Always runs regardless of the auto-sync
    /// setting; this is the path the "Sync Now" button takes. `force: true`
    /// reloads the widgets unconditionally (the user asked for a refresh)
    /// rather than only when the widget-visible data changed.
    public func pokeNow() async {
        await poke(container: container, force: true)
    }

    private func poke(container: ModelContainer, force: Bool = false) async {
        // 1. Local save (SwiftData ops must run on MainActor).
        let saveError: String? = await MainActor.run {
            // Save the LIVE main context — the one the UI's edits live in.
            // A throwaway `ModelContext(container)` has no pending changes,
            // so saving it was a no-op; UI edits only reached disk via
            // SwiftData autosave. Saving `mainContext` guarantees the shared
            // SQLite is current before we push to CloudKit and reload the
            // widgets (which read that same file from another process).
            let context = container.mainContext
            do {
                try context.save()
            } catch {
                let msg = error.localizedDescription
                DorisLog.sync.error("local save failed: \(msg, privacy: .public)")
                // Still try to purge tombstones — they don't depend on the
                // dirty write that just failed.
                Self.purgeTombstones(context: context)
                return Self.localized(
                    en: "Local save failed: \(msg)",
                    zh: "本地保存失败:\(msg)"
                )
            }
            Self.purgeTombstones(context: context)
            return nil
        }
        if let saveError {
            await MainActor.run { SyncSettings.shared.lastSyncError = saveError }
            return
        }

        // 2. If CloudKit is on, verify it's actually reachable. Without
        //    this, `context.save()` returning success means **nothing**
        //    about the cloud round-trip — SwiftData's CloudKit mirror is
        //    asynchronous and silent on failure.
        let cloudKitEnabled = await MainActor.run { SyncSettings.shared.cloudKitEnabled }
        if cloudKitEnabled {
            // 2a. The user asked for iCloud, but did the live container
            //     actually get it? `DorisRuntime`'s fallback chain can quietly
            //     hand back a local-only store; reporting "synced" for that is
            //     how a store can sit arbitrarily stale behind a green label.
            if await MainActor.run { SyncSettings.shared.cloudKitDegraded } {
                let msg = Self.localized(
                    en: "iCloud is on, but this app is running on a local-only store — nothing is syncing. Restart Doris; if it persists, check the app's signing / iCloud entitlements.",
                    zh: "iCloud 已开启,但当前运行的是纯本地存储 —— 实际没有在同步。请重启 Doris;若仍如此,检查签名 / iCloud 权限。"
                )
                await MainActor.run { SyncSettings.shared.lastSyncError = msg }
                DorisLog.sync.error("poke: cloudKitEnabled but container is local-only")
                return
            }
            if let cloudError = await Self.verifyCloudKit() {
                await MainActor.run { SyncSettings.shared.lastSyncError = cloudError }
                DorisLog.sync.error("cloud verify failed: \(cloudError, privacy: .public)")
                return
            }
            // 2b. Inbound changes arrive via CloudKit subscription pushes. If
            //     APNs registration failed we can still push our own edits, so
            //     this isn't a hard failure — but it must not read as "synced",
            //     because remote edits will never land.
            if await MainActor.run { !SyncSettings.shared.inboundPushReady } {
                let msg = Self.localized(
                    en: "Sending changes works, but this device can't receive push notifications — changes made on your other devices won't arrive. Check Settings → Notifications for Doris.",
                    zh: "本机的改动能发出去,但收不到推送通知 —— 其他设备上的改动不会同步过来。请检查系统设置 → 通知 里 Doris 的权限。"
                )
                await MainActor.run { SyncSettings.shared.lastSyncError = msg }
                DorisLog.sync.error("poke: inbound push unavailable — import will not happen")
                return
            }
        }

        // 3. Success path — only here do we update lastSyncedAt, and only when
        //    iCloud is actually on. With sync off, all that happened is a local
        //    save; stamping "last synced" for that made the Settings row read
        //    as though data had reached the cloud.
        await MainActor.run {
            if cloudKitEnabled {
                SyncSettings.shared.markSyncedNow()
            }
            SyncSettings.shared.lastSyncError = nil
            DorisLog.sync.debug("sync poke ok (cloudKit=\(cloudKitEnabled))")
            // 4. Kick the home-screen widgets. SQLite just got fresh data
            //    (local edits we flushed above, or CloudKit inbound rows the
            //    mirror applied). A manual "Sync Now" forces a reload; the
            //    60-second auto tick only reloads when the widget-visible
            //    data actually changed, so we don't burn WidgetKit's reload
            //    budget on no-op ticks (which would get the *meaningful*
            //    reload throttled away).
            if force {
                WidgetReloadCoordinator.forceReload(container: container)
            } else {
                WidgetReloadCoordinator.reloadIfChanged(container: container)
            }
        }
    }

    /// Reachability probe for the private CloudKit container. Two cheap
    /// async calls: `accountStatus()` to learn whether there's an Apple
    /// ID signed in at all, then `userRecordID()` as an actual network
    /// roundtrip — together they catch every realistic failure mode
    /// (no account, restricted, no network, server unreachable).
    /// Returns `nil` on success or a localized error string otherwise.
    private static func verifyCloudKit() async -> String? {
        // Refuse to even instantiate CKContainer on unsigned dev builds —
        // `CKContainer.init(identifier:)` itself traps the process with
        // brk 1 when the running binary declares iCloud entitlements but
        // wasn't signed with a Development Team. Same root cause as
        // SwiftData's mirror crash on launch; we keep one check here so
        // tapping "Sync Now" stays safe even when the user has the
        // CloudKit toggle on.
        guard CodeSigningCheck.hasTeamIdentifier else {
            return localized(
                en: "App is not signed with a Development Team — iCloud sync disabled.",
                zh: "App 没有用开发证书签名 — iCloud 同步已禁用。"
            )
        }
        let container = CKContainer(identifier: DorisIdentifiers.cloudKitContainer)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                _ = try await container.userRecordID()
                return nil
            case .noAccount:
                return localized(
                    en: "No iCloud account signed in on this device",
                    zh: "此设备未登录 iCloud 账号"
                )
            case .restricted:
                return localized(
                    en: "iCloud is restricted on this device",
                    zh: "iCloud 在此设备上被限制"
                )
            case .couldNotDetermine:
                return localized(
                    en: "Couldn't reach iCloud",
                    zh: "无法连接 iCloud"
                )
            case .temporarilyUnavailable:
                return localized(
                    en: "iCloud temporarily unavailable",
                    zh: "iCloud 暂时不可用"
                )
            @unknown default:
                return localized(
                    en: "Unknown iCloud account state",
                    zh: "未知 iCloud 账号状态"
                )
            }
        } catch {
            return localized(
                en: "iCloud: \(error.localizedDescription)",
                zh: "iCloud:\(error.localizedDescription)"
            )
        }
    }

    /// Tiny EN/ZH switcher. `DorisCore` doesn't depend on `DorisUI`, so we
    /// read the same UserDefaults key the `L()` helper in DorisUI writes
    /// to. Default is Chinese to match `LanguageSettings`'s default.
    private static func localized(en: String, zh: String) -> String {
        let mode = UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh"
        return mode == "en" ? en : zh
    }

    /// Hard-deletes notes that have been soft-deleted (either `archived
    /// = true` or `deleted = true`) for long enough that we trust every
    /// device has seen the soft-delete and won't resurrect the record
    /// via CloudKit mirror race.
    ///
    /// Two cutoffs because the two flags carry different intent:
    /// - `archived` = "Recently Deleted" — user can still restore, so
    ///   we give it a full 30 days before hard-deleting.
    /// - `deleted` = "Trash" — explicit user-intent to permanently
    ///   delete, just gated by a quorum window. 24 hours is enough for
    ///   any active device to pull the tombstone update on its next
    ///   sync cycle.
    ///
    /// Must be called on the main actor (`ModelContext` is main-bound).
    @MainActor
    private static func purgeTombstones(context: ModelContext) {
        let now = Date()
        let archivedCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let trashCutoff = now.addingTimeInterval(-24 * 60 * 60)
        // Two FetchDescriptors instead of one OR-predicate because
        // SwiftData's #Predicate has limited support for complex
        // boolean compositions involving multiple optional Dates.
        let archivedDesc = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.archived && $0.updatedAt < archivedCutoff }
        )
        let deletedDesc = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.deleted && $0.updatedAt < trashCutoff }
        )
        let staleArchived = (try? context.fetch(archivedDesc)) ?? []
        let staleDeleted = (try? context.fetch(deletedDesc)) ?? []
        // Dedupe — a record can satisfy both predicates (archived AND
        // deleted) — to avoid double-deleting.
        var seen = Set<UUID>()
        var stale: [Note] = []
        for n in staleArchived + staleDeleted where seen.insert(n.id).inserted {
            stale.append(n)
        }
        guard !stale.isEmpty else { return }
        for note in stale {
            context.delete(note)
        }
        try? context.save()
        DorisLog.sync.debug("purged \(stale.count) tombstoned note(s)")
    }
}
