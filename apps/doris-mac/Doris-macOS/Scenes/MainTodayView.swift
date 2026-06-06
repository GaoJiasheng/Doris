import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// macOS "Today" surface — first tab of the main window. Visual
/// vocabulary follows the iOS Today screen one-to-one (same weather
/// card, pinned grid, upcoming list), since the three card types live
/// in `DorisUI/Today/TodayComponents.swift` and are imported by both
/// platforms.
///
/// The screen *wrapper* diverges from iOS because mac uses
/// NavigationSplitView + an `editing: Note?` binding (rather than
/// NavigationStack + NavigationPath). Tapping any pinned card or
/// upcoming row sets the binding; the parent (`MainWindowView`) swaps
/// to `InlineNoteEditor` for the whole detail pane. That keeps Today's
/// "open a note" feel identical to the TODO tab's.
///
/// One macOS-only tweak: the pinned grid uses an adaptive column
/// layout (`GridItem(.adaptive(minimum: 180))`) instead of the iOS
/// fixed 2-column grid, so wider windows naturally fan out to 3 or 4
/// columns without wasted space.
struct MainTodayView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx
    // Weather lives on the sidebar avatar already — no second copy in
    // the Today pane. The date strip below stays as the "this is Today"
    // anchor.

    @Query(
        filter: #Predicate<Note> { note in !note.archived && !note.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var allNotes: [Note]

    /// Binding lifted from `MainWindowView` — same one that the TODO
    /// tab uses, so opening a note from Today goes through the exact
    /// same editor path (and parent hides the detail header etc.).
    @Binding var editing: Note?

    /// Pinned notes sorted by urgency:
    ///   1. Notes with a `dueDate` come first, sorted ascending (most
    ///      overdue → today → soonest future).
    ///   2. Notes without a `dueDate` come after, sorted by `updatedAt`
    ///      descending (most recently touched first).
    /// Regular "置顶" pins (pinned, not long-term).
    private var regularPinnedNotes: [Note] {
        pinnedSorted(allNotes.filter { $0.pinned && !$0.longTerm })
    }

    /// "长期" / long-term pins — a distinct bucket the user keeps around
    /// indefinitely, shown under its own header below the regular pins.
    private var longTermNotes: [Note] {
        pinnedSorted(allNotes.filter { $0.pinned && $0.longTerm })
    }

    /// Shared sort for pinned buckets. Manual drag-order wins first (all
    /// 0 until the user reorders, so legacy/un-dragged sets fall through
    /// to the due-date / recency ordering below).
    private func pinnedSorted(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            switch (a.dueDate, b.dueDate) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.updatedAt > b.updatedAt
            }
        }
    }

    /// Notes with a due date, minus the "past and already completed"
    /// rows that are no longer actionable. Overdue (past + not done)
    /// still surfaces so the user knows what's been hanging. Today &
    /// future show regardless of completion state — strikethrough
    /// visuals carry the "this is done" signal there.
    private var calendarNotes: [Note] {
        allNotes
            .filter { $0.dueDate != nil && !$0.isPastAndCompleted() }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        // Same pattern as `MainNotesList`: when `editing` is set we
        // swap the entire tab body to the inline editor. The parent
        // (`MainWindowView.detail`) hides the detail header in that
        // same condition, so the editor gets the full pane.
        Group {
            if let editing {
                InlineNoteEditor(note: editing) { self.editing = nil }
            } else {
                scrollBody
            }
        }
    }

    private var scrollBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // The date is rendered up in `MainWindowView`'s detail
                // header (next to the tab strip, only while Today is
                // active) so the scroll content can lead directly with
                // the actual content — saves a row of vertical space
                // that was otherwise just visual chrome. iOS Today also
                // shows a weather card here; we skip it on mac because
                // the sidebar avatar already carries the weather pill.

                // ── Pinned ──────────────────────────────────────────────
                // Pinned uses pink to read as "attention worthy"
                // (user-flagged stuff), Upcoming uses cyan as the
                // calmer schedule color, Long-term gets its own violet.
                if !regularPinnedNotes.isEmpty {
                    sectionHeader(
                        icon: "pin.fill",
                        title: L("Pinned", "置顶"),
                        tint: CyberPalette.neonPink
                    )
                    pinnedGrid(regularPinnedNotes)
                }

                // ── Long-term ───────────────────────────────────────────
                if !longTermNotes.isEmpty {
                    sectionHeader(
                        icon: "infinity",
                        title: L("Long-term", "长期"),
                        tint: Color(red: 0.62, green: 0.51, blue: 1.0)
                    )
                    pinnedGrid(longTermNotes)
                }

                // ── Upcoming ────────────────────────────────────────────
                if !calendarNotes.isEmpty {
                    sectionHeader(
                        icon: "calendar",
                        title: L("Upcoming", "日程"),
                        tint: CyberPalette.neonCyan
                    )
                    VStack(spacing: 8) {
                        ForEach(calendarNotes) { n in
                            Button { editing = n } label: {
                                TodayCalendarRow(note: n)
                            }
                            .buttonStyle(.plain)
                            .noteContextMenu(for: n, onOpenEditor: { editing = n })
                        }
                    }
                }

                if regularPinnedNotes.isEmpty && longTermNotes.isEmpty && calendarNotes.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Pinned grid

    /// Shared card grid used by both the 置顶 and 长期 buckets. Cards are
    /// draggable to reorder within their bucket; the drop renumbers
    /// `note.order` so the manual order persists (and syncs via
    /// CloudKit).
    @ViewBuilder
    private func pinnedGrid(_ notes: [Note]) -> some View {
        LazyVGrid(
            // Bumped from 180 → 270 (+50%) so cards read chunkier; at the
            // default 760pt window width that lands 1 column, fanning out
            // to 2+ as the window widens.
            columns: [GridItem(.adaptive(minimum: 270), spacing: 10)],
            spacing: 10
        ) {
            ForEach(notes) { n in
                Button { editing = n } label: {
                    TodayPinnedCard(note: n)
                }
                .buttonStyle(.plain)
                .noteContextMenu(for: n, onOpenEditor: { editing = n })
                .draggable(n.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first,
                          let dragged = UUID(uuidString: raw),
                          dragged != n.id else { return false }
                    reorderPinned(dragged: dragged, before: n.id, within: notes)
                    return true
                }
            }
        }
    }

    /// Renumber `order` across the bucket so the dragged card lands
    /// before `targetID`. Mirrors MainWindowView.moveDraggedBefore.
    private func reorderPinned(dragged: UUID, before targetID: UUID, within notes: [Note]) {
        guard let draggedNote = notes.first(where: { $0.id == dragged }) else { return }
        var arr = notes.filter { $0.id != dragged }
        let idx = arr.firstIndex(where: { $0.id == targetID }) ?? arr.count
        arr.insert(draggedNote, at: idx)
        for (i, n) in arr.enumerated() { n.order = Double(i) }
        draggedNote.touch()
        try? ctx.save()
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .kerning(2)
            Rectangle()
                .fill(tint.opacity(0.18))
                .frame(height: 0.6)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.45))
            Text(L("All clear", "今日清净"))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.65))
            Text(L("Pin a note or set a due date to see it here.",
                   "置顶笔记或设定截止日期即可出现在这里。"))
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
