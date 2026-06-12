import Foundation
import SwiftData
import DorisIPC
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Centralizes home-screen / desktop widget reloads.
///
/// `WidgetCenter.reloadAllTimelines()` is only a *request* — WidgetKit
/// budgets how often a widget may actually refresh (a few dozen times a
/// day). The old code asked for a reload on *every* 60-second sync tick
/// regardless of whether anything changed, plus every foreground/background
/// transition. On an active day that exhausts the budget, and then the one
/// reload that matters — right after you edit or sync — gets silently
/// dropped, leaving the widget stale until WidgetKit's ~hourly floor. That
/// is the "I synced but the widget didn't update" symptom.
///
/// `reloadIfChanged` fixes it by computing a deterministic signature of
/// exactly the data the widgets render (pinned + dated notes) and only
/// requesting a reload when that signature differs from the last reload —
/// so no-op ticks cost nothing and the meaningful reloads always land.
/// `forceReload` bypasses the gate for explicit user actions (manual
/// "Sync Now" / pull-to-refresh).
///
/// The signature lives in the App-Group `UserDefaults` so it survives
/// relaunch and is shared across the app + extensions. It is hashed with
/// FNV-1a over UTF-8 bytes — NOT Swift's `Hasher`, whose seed is
/// randomized per process and would never match across launches.
@MainActor
public enum WidgetReloadCoordinator {
    private static let signatureKey = "doris.widget.contentSignature"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: DorisIdentifiers.appGroup) ?? .standard
    }

    /// Reload widgets only if the widget-visible data changed since the
    /// last reload. Cheap + safe to call on every sync tick. Returns
    /// `true` if a reload was actually requested.
    @discardableResult
    public static func reloadIfChanged(container: ModelContainer) -> Bool {
        let sig = signature(container: container)
        guard sig != sharedDefaults.string(forKey: signatureKey) else { return false }
        sharedDefaults.set(sig, forKey: signatureKey)
        requestReload(reason: "content changed")
        return true
    }

    /// Force an unconditional reload (explicit user refresh). Also refreshes
    /// the stored signature so the next `reloadIfChanged` compares against
    /// the current state rather than re-firing.
    public static func forceReload(container: ModelContainer) {
        sharedDefaults.set(signature(container: container), forKey: signatureKey)
        requestReload(reason: "forced")
    }

    private static func requestReload(reason: String) {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        DorisLog.sync.debug("widget reload requested (\(reason, privacy: .public))")
        #endif
    }

    /// Deterministic digest of every field the widgets render, over the
    /// notes they actually show (pinned, or carrying a due date). Any edit
    /// bumps `Note.updatedAt`, so hashing it captures title / done /
    /// checklist / due / pin / order changes; the membership filter
    /// (`pinned || dueDate != nil`) captures a note entering or leaving the
    /// widget's buckets. Mirrors `TasksProvider.load()`'s fetch.
    static func signature(container: ModelContainer) -> String {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.archived && !$0.deleted }
        )
        let rows = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.pinned || $0.dueDate != nil }
            .map { n -> String in
                let due = n.dueDate.map { String($0.timeIntervalSince1970) } ?? "-"
                let prog = n.checklistProgress.map { "\($0.done)/\($0.total)" } ?? "-"
                return [
                    n.id.uuidString,
                    String(n.updatedAt.timeIntervalSince1970),
                    n.pinned ? "p" : "-",
                    n.longTerm ? "l" : "-",
                    n.done ? "d" : "-",
                    due,
                    String(n.order),
                    prog
                ].joined(separator: ":")
            }
            .sorted()
        return fnv1a(rows.joined(separator: "|"))
    }

    private static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
