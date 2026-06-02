import WidgetKit
import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Home-screen widget showing the user's focus tasks — pinned TODOs +
/// anything due today/overdue that isn't done yet — with checklist
/// progress. Complements the EventsWidget (which shows inbound events);
/// this one is the "what should I be doing" surface.
struct TasksWidget: Widget {
    let kind: String = "com.gavin.doris.widget.tasks"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Doris Tasks")
        .description("Pinned + today's tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskSnapshot]
    /// Total focus tasks before truncation, so the view can show "+N more".
    let total: Int
}

struct TaskSnapshot: Identifiable {
    let id: UUID
    let title: String
    let done: Bool
    let pinned: Bool
    let checklistDone: Int
    let checklistTotal: Int
    let dueDate: Date?
}

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: .now, tasks: [], total: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        // Refresh hourly + at the next start-of-day so "due today" stays
        // accurate as the day rolls over. WidgetKit also refreshes on
        // app foreground transitions, so this is just the floor.
        let next = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> TasksEntry {
        guard let container = try? ModelContainerFactory.make(useCloudKit: true) else {
            return TasksEntry(date: .now, tasks: [], total: 0)
        }
        let context = ModelContext(container)
        // Pull active (not archived/deleted/done) notes; filter to the
        // "focus" set in Swift since the pinned-OR-due-today rule is
        // awkward to express as a single #Predicate.
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.archived && !$0.deleted && !$0.done },
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 60
        let all = (try? context.fetch(descriptor)) ?? []

        let startOfTomorrow = Calendar.current
            .startOfDay(for: Date())
            .addingTimeInterval(24 * 60 * 60)
        let focus = all.filter { n in
            if n.pinned { return true }
            if let due = n.dueDate { return due < startOfTomorrow }   // overdue or due today
            return false
        }
        // Due (soonest/overdue) first, then pinned, then manual order.
        let sorted = focus.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (l?, r?) where l != r: return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.pinned != b.pinned { return a.pinned && !b.pinned }
                return a.order < b.order
            }
        }

        let snapshots = sorted.prefix(8).map { n -> TaskSnapshot in
            let p = n.checklistProgress
            return TaskSnapshot(
                id: n.id,
                title: n.title.isEmpty ? "Untitled" : n.title,
                done: n.done,
                pinned: n.pinned,
                checklistDone: p?.done ?? 0,
                checklistTotal: p?.total ?? 0,
                dueDate: n.dueDate
            )
        }
        return TasksEntry(date: .now, tasks: Array(snapshots), total: focus.count)
    }
}

struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    private var visibleCount: Int {
        switch family {
        case .systemSmall:        return 3
        case .systemMedium:       return 3
        case .systemLarge:        return 7
        case .accessoryRectangular: return 2
        default:                  return 3
        }
    }

    var body: some View {
        if entry.tasks.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("All clear")
                    .font(.caption)
            }
        } else if family == .accessoryRectangular {
            // Lock-screen: count + first task title.
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.total) task\(entry.total == 1 ? "" : "s")")
                    .font(.caption2.weight(.semibold))
                if let first = entry.tasks.first {
                    Text(first.title).font(.caption2).lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
                HStack {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                    Text("Tasks")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Text("\(entry.total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(entry.tasks.prefix(visibleCount)) { t in
                    row(t)
                }
                let hidden = entry.total - min(visibleCount, entry.tasks.count)
                if hidden > 0 {
                    Text("+\(hidden) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(family == .systemSmall ? 8 : 10)
        }
    }

    @ViewBuilder
    private func row(_ t: TaskSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: t.checklistTotal > 0 ? "checklist" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(t.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            if t.checklistTotal > 0 {
                Text("\(t.checklistDone)/\(t.checklistTotal)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let due = t.dueDate {
                Text(due, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(due < Date() ? .red : .secondary)
            }
        }
    }
}
