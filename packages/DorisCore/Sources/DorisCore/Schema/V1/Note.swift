import Foundation
import DorisIPC
import SwiftData

@Model
public final class Note {
    public var id: UUID = UUID()
    public var title: String = ""
    public var bodyMarkdown: String = ""
    public var isChecklist: Bool = false
    public var pinned: Bool = false
    /// Sub-flag of `pinned`: when a pinned note also has `longTerm`,
    /// it lives in the "长期 / Long-term" bucket of the Today pinned
    /// area instead of the regular "置顶 / Pinned" bucket. Both are
    /// pinned (so every existing `pinned` filter / "pinned first" sort
    /// still applies); this only splits how they're grouped + labeled.
    /// A non-pinned note is never long-term.
    public var longTerm: Bool = false
    public var archived: Bool = false
    /// Top-level "task done" state. Each Note IS a TODO item — the
    /// list view shows a checkbox per row; tick it to mark this whole
    /// note complete. Independent of any in-body checklist items
    /// (those live in `bodyMarkdown` as `- [x]` markers).
    public var done: Bool = false
    /// Timestamp when `done` flipped from false → true. Cleared back to
    /// `nil` when `done` flips back to false. Used by the future
    /// "archive yesterday's completed tasks" automation.
    public var completedAt: Date?
    /// Timestamp when `archived` flipped from false → true. Cleared
    /// back to `nil` on un-archive. Lets the archived view sort by
    /// "most recently archived first" (more useful than `updatedAt`
    /// for digging through old tasks).
    public var archivedAt: Date?
    /// Soft-delete flag — `true` means the row is in the trash view,
    /// recoverable. The user requested this so the regular delete
    /// button doesn't need a confirmation dialog (mistakes can be
    /// undone from Trash). Hard-delete (truly removing the row) only
    /// happens from inside the trash view.
    public var deleted: Bool = false
    /// Timestamp when `deleted` flipped from false → true. Cleared on
    /// restore. Used to sort the Trash view newest-first.
    public var deletedAt: Date?
    /// Manual sort key for drag-and-drop reordering. Lower value =
    /// higher in the list within the same pinned/done group. Default 0
    /// for legacy rows (they fall back to `createdAt` ordering via the
    /// secondary sort). Stored as Double so we can sandwich a new
    /// note between two existing rows by averaging their orders
    /// without renumbering everything.
    public var order: Double = 0
    public var colorHex: String?
    /// Due date for calendar/Today view. nil = no due date.
    /// Added in SchemaV2; existing notes get nil via lightweight migration.
    public var dueDate: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var folder: Folder?
    public var tags: [Tag]? = []
    public var promotedFrom: Message?

    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.note)
    public var checklistItems: [ChecklistItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Attachment.note)
    public var attachments: [Attachment]? = []

    public init(
        id: UUID = UUID(),
        title: String = "",
        bodyMarkdown: String = "",
        isChecklist: Bool = false,
        pinned: Bool = false,
        archived: Bool = false,
        colorHex: String? = nil,
        dueDate: Date? = nil,
        folder: Folder? = nil
    ) {
        self.id = id
        self.title = title
        self.bodyMarkdown = bodyMarkdown
        self.isChecklist = isChecklist
        self.pinned = pinned
        self.archived = archived
        self.colorHex = colorHex
        self.dueDate = dueDate
        self.folder = folder
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    // MARK: - Helpers

    /// Stamps `updatedAt` to now. Use this instead of setting `updatedAt`
    /// directly — single chokepoint for all "note was modified" signals,
    /// important for CloudKit merge-conflict disambiguation.
    public func touch() {
        updatedAt = Date()
    }

    /// Soft-delete: marks the note archived and stamps updatedAt. Use this
    /// instead of `modelContext.delete(note)` so CloudKit propagates the
    /// archived flag to other devices. SyncTimer auto-purges records that
    /// have been archived for 30+ days via a hard delete.
    public func archive() {
        archived = true
        touch()
    }

    /// Single source of truth for checklist progress, derived live from
    /// `bodyMarkdown`. The `checklistItems` relationship above is legacy
    /// and is not written by any current editor — the editor stores task
    /// state inline as `- [ ]` / `- [x]` lines in the markdown body
    /// (see `DorisUI.ChecklistEditorView`). Returns nil when the note
    /// isn't a checklist or has no checkbox lines.
    public var checklistProgress: (done: Int, total: Int)? {
        guard isChecklist else { return nil }
        var done = 0
        var total = 0
        for raw in bodyMarkdown.components(separatedBy: "\n") {
            if raw.hasPrefix("- [ ]") {
                total += 1
            } else if raw.hasPrefix("- [x]") || raw.hasPrefix("- [X]") {
                total += 1
                done += 1
            }
        }
        return total > 0 ? (done, total) : nil
    }

    /// Folds note-level done state and "every checklist item ticked"
    /// into a single bool that the UI can key its completed-state
    /// visuals & "hide past-done from calendar" filters off. Earlier
    /// implementations in TodayComponents.swift / NoteRow / etc. read
    /// `checklistItems` directly — that's the legacy relationship and
    /// is never written, so the all-items-done branch silently never
    /// fired. Centralising here so the bug is fixed for every caller
    /// at once.
    public var isCompleted: Bool {
        if done { return true }
        if let p = checklistProgress, p.total > 0, p.done == p.total {
            return true
        }
        return false
    }

    /// True when the note has a due date that's strictly before today
    /// (start-of-day in the user's calendar) AND it isn't completed.
    /// "Overdue" = "should have been done by now but isn't". Drives
    /// the calendar's red overdue section.
    public func isOverdue(now: Date = Date(),
                          calendar: Calendar = .current) -> Bool {
        guard let due = dueDate else { return false }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        return dueDay < today && !isCompleted
    }

    /// True when the note's due date is strictly before today AND it's
    /// already completed. These are the rows the calendar views hide
    /// by default — past, settled, no-longer-actionable.
    public func isPastAndCompleted(now: Date = Date(),
                                   calendar: Calendar = .current) -> Bool {
        guard let due = dueDate else { return false }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        return dueDay < today && isCompleted
    }
}
