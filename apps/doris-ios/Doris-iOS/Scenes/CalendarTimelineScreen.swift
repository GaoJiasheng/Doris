import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Calendar-timeline view reached from the calendar button in the Notes
/// toolbar. Notes are grouped into sections by their `dueDate`, ordered
/// chronologically (Overdue → Today → Tomorrow → each upcoming day →
/// Unscheduled at the bottom). Empty sections are skipped.
///
/// This is the "full list" complement to the Today tab dashboard —
/// Today shows the highlight reel (weather + pinned + a few items),
/// this screen is the exhaustive agenda.
struct CalendarTimelineScreen: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx

    @Query(
        // Excludes trashed rows too (`deleted` is a soft-delete flag), so a
        // note in the Trash stops occupying its due date on the timeline.
        filter: #Predicate<Note> { note in !note.archived && !note.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var allNotes: [Note]

    // MARK: - Section model

    private struct Section: Identifiable {
        let id: String
        let label: String
        let icon: String
        let tint: Color
        let notes: [Note]
    }

    private var sections: [Section] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var overdue: [Note] = []
        var todayNotes: [Note] = []
        var tomorrowNotes: [Note] = []
        var dated: [Date: [Note]] = [:]
        var unscheduled: [Note] = []

        for note in allNotes {
            guard let due = note.dueDate else {
                unscheduled.append(note)
                continue
            }
            let dueDay = cal.startOfDay(for: due)
            if dueDay < today {
                // Past dates: only show overdue (uncompleted) rows.
                // Past + completed are dropped entirely so the timeline
                // doesn't fill up with yesterday's settled tasks. Users
                // who want to see them can flip the row back to "not
                // done" or look at the Notes tab archive.
                if !note.isCompleted {
                    overdue.append(note)
                }
            } else if cal.isDateInToday(due) {
                todayNotes.append(note)
            } else if cal.isDateInTomorrow(due) {
                tomorrowNotes.append(note)
            } else {
                dated[dueDay, default: []].append(note)
            }
        }

        var sections: [Section] = []

        if !overdue.isEmpty {
            let sorted = overdue.sorted {
                ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            sections.append(Section(
                id: "overdue",
                label: L("Overdue", "已逾期"),
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                notes: sorted
            ))
        }
        if !todayNotes.isEmpty {
            sections.append(Section(
                id: "today",
                label: L("Today", "今天"),
                icon: "sun.max.fill",
                tint: .yellow,
                notes: todayNotes
            ))
        }
        if !tomorrowNotes.isEmpty {
            sections.append(Section(
                id: "tomorrow",
                label: L("Tomorrow", "明天"),
                icon: "sunrise.fill",
                tint: CyberPalette.neonCyan,
                notes: tomorrowNotes
            ))
        }
        for day in dated.keys.sorted() {
            let notes = (dated[day] ?? []).sorted {
                ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            let days = cal.dateComponents([.day], from: today, to: day).day ?? 0
            let label: String = days < 7
                ? day.formatted(.dateTime.weekday(.wide))
                : day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            sections.append(Section(
                id: ISO8601DateFormatter().string(from: day),
                label: label,
                icon: "calendar",
                tint: CyberPalette.neonCyan,
                notes: notes
            ))
        }
        if !unscheduled.isEmpty {
            sections.append(Section(
                id: "unscheduled",
                label: L("Unscheduled", "未排期"),
                icon: "tray",
                tint: .primary.opacity(0.5),
                notes: unscheduled.sorted { $0.updatedAt > $1.updatedAt }
            ))
        }
        return sections
    }

    var body: some View {
        Group {
            if sections.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections) { section in
                        SwiftUI.Section {
                            ForEach(section.notes) { n in
                                NavigationLink(value: n.id) {
                                    TimelineNoteRow(note: n, accent: section.tint)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                // Long-press → shared note action menu
                                // (Schedule / Done / Done&archive /
                                // Pin / Archive / Trash) so users can
                                // act on a calendar row without
                                // drilling into the detail screen.
                                .noteContextMenu(for: n)
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { navTitle }
        }
        .navigationDestination(for: UUID.self) { id in
            if let note = allNotes.first(where: { $0.id == id }) {
                NoteDetailScreen(note: note) {}
            }
        }
    }

    // MARK: - Nav title

    private var navTitle: some View {
        VStack(spacing: 1) {
            Text(L("Timeline", "时间轴"))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(L("AGENDA", "日程"))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.85))
                .kerning(2.5)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ section: Section) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(section.tint)
            Text(section.label.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(section.tint)
                .kerning(1.8)
            Text("· \(section.notes.count)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                .foregroundStyle(section.tint.opacity(0.55))
            Rectangle()
                .fill(section.tint.opacity(0.18))
                .frame(height: 0.6)
        }
        .textCase(nil)
        .padding(.top, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 42))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.45))
            Text(L("Nothing scheduled", "暂无安排"))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.65))
            Text(L("Set a due date on a note to see it in the timeline.",
                   "在笔记上设置截止日期即可出现在时间轴上。"))
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Timeline row

private struct TimelineNoteRow: View {
    let note: Note
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: note.isChecklist ? "checklist" : "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                bottomMeta
            }

            Spacer(minLength: 0)

            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(CyberPalette.neonCyan.opacity(0.6))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.15), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var bottomMeta: some View {
        if let p = note.checklistProgress {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(p.done)/\(p.total)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
            }
            .foregroundStyle(.primary.opacity(0.5))
        } else if let due = note.dueDate {
            Text(due, format: .dateTime.hour().minute())
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.4))
        }
    }
}
