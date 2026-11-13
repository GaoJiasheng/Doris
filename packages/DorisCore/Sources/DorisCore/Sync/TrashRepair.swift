import Foundation
import SwiftData

/// One-time repair for notes the trash bug brought back.
///
/// Until 1.14.5 the trash was the `deleted` flag, which never synced (see
/// `Note.deleted`): a trashed note came back on its next import, with its
/// `deletedAt` still set. The trash is now `deletedAt != nil`, so notes
/// left that way would suddenly read as trashed — and the purge would
/// hard-delete the ones trashed long ago. Before anything reads the new
/// rule, each device sorts them out once, from synced timestamps only, so
/// every device decides the same:
///
/// - Edited after it was trashed: you kept using it. It stays, and
///   `deletedAt` is cleared.
/// - Untouched since: it goes back to the trash, stamped now, so it gets a
///   fresh 24 hours there before the purge.
public enum TrashRepair {
    static let doneKey = "doris.trashRepair.v1"

    /// Edits this soon after the trash stamp still count as "untouched":
    /// the trash itself and a save right after it.
    static let grace: TimeInterval = 60

    enum Decision: Equatable { case leave, keep, trash }

    static func decide(deleted: Bool, deletedAt: Date?, updatedAt: Date) -> Decision {
        guard let deletedAt else {
            // In the trash only by the old flag (from before `deletedAt`).
            return deleted ? .trash : .leave
        }
        return updatedAt.timeIntervalSince(deletedAt) > grace ? .keep : .trash
    }

    /// Runs the repair unless this device already has.
    @MainActor
    public static func runOnce(context: ModelContext, defaults: UserDefaults = .standard, now: Date = Date()) {
        guard !defaults.bool(forKey: doneKey) else { return }
        guard let notes = try? context.fetch(FetchDescriptor<Note>()) else { return }
        var kept = 0, trashed = 0
        for note in notes {
            switch decide(deleted: note.deleted, deletedAt: note.deletedAt, updatedAt: note.updatedAt) {
            case .leave:
                continue
            case .keep:
                note.deleted = false
                note.deletedAt = nil
                kept += 1
            case .trash:
                note.deleted = true
                note.deletedAt = now
                note.updatedAt = now
                trashed += 1
            }
        }
        do {
            try context.save()
            defaults.set(true, forKey: doneKey)
            DorisLog.sync.info("trash repair: kept \(kept), back in trash \(trashed)")
        } catch {
            DorisLog.sync.error("trash repair save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
