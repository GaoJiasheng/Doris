import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import DorisCore
import DorisUI

// MARK: - Interactive toggle (capability parity with the macOS desktop panel)

/// Tap-to-complete from the home screen. Mirrors the macOS DesktopPanelView
/// checkbox: flips `done`, stamps/clears `completedAt`, bumps `updatedAt`,
/// then asks WidgetKit to redraw. Runs in the widget extension process
/// against the same App-Group + CloudKit store the app uses, so the change
/// syncs back to every surface.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Task Done"
    static var isDiscoverable: Bool = false   // widget-only, keep out of Shortcuts/Spotlight

    @Parameter(title: "Note ID")
    var noteID: String

    init() {}
    init(noteID: String) { self.noteID = noteID }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: noteID),
              let container = try? ModelContainerFactory.make(useCloudKit: true) else {
            return .result()
        }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        if let note = try? context.fetch(descriptor).first {
            let now = Date()
            note.done.toggle()
            note.completedAt = note.done ? now : nil
            note.updatedAt = now
            try? context.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Widget

/// Home-screen widget showing the user's focus tasks — pinned (置顶 + 长期)
/// and today/upcoming (日程) — with tap-to-complete checkboxes and checklist
/// progress. Capability-aligned with the macOS desktop panel; the UI is a
/// dressed-up version: adaptive cyber gradient, per-section accent rails,
/// progress pills.
struct TasksWidget: Widget {
    let kind: String = "com.gavin.doris.widget.tasks"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Doris · 今日")
        .description("置顶 + 今日待办，点一下即可勾选完成。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Model

enum TaskSection {
    case pinned     // 置顶 + 长期
    case upcoming   // 日程
}

struct TaskSnapshot: Identifiable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let section: TaskSection
    let longTerm: Bool
    let checklistDone: Int
    let checklistTotal: Int
    let dueDate: Date?
    let overdue: Bool

    /// Section/long-term accent used for the rail + empty checkbox.
    var tint: Color {
        switch section {
        case .pinned:   return longTerm ? CyberPalette.longTermViolet : CyberPalette.neonPink
        case .upcoming: return CyberPalette.neonCyan
        }
    }
}

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskSnapshot]
    let pinnedTotal: Int
    let upcomingTotal: Int
    var total: Int { pinnedTotal + upcomingTotal }
}

// `长期` violet — kept local so the widget needn't reach into app code.
private extension CyberPalette {
    static let longTermViolet = Color(red: 0.62, green: 0.51, blue: 1.0)
}

// MARK: - Provider

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(date: .now, tasks: [], pinnedTotal: 0, upcomingTotal: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        // Refresh hourly so "due today / overdue" stays accurate as the day
        // rolls over. WidgetKit also reloads on the toggle intent + app
        // foreground transitions, so this is just the floor.
        let next = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    private func load() -> TasksEntry {
        guard let container = try? ModelContainerFactory.make(useCloudKit: true) else {
            return TasksEntry(date: .now, tasks: [], pinnedTotal: 0, upcomingTotal: 0)
        }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.archived && !$0.deleted },
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 120
        let all = (try? context.fetch(descriptor)) ?? []

        // Mirror DesktopPanelView's buckets exactly.
        let pinned = all
            .filter { $0.pinned }
            .sorted { a, b in
                if a.longTerm != b.longTerm { return !a.longTerm && b.longTerm }  // 置顶 before 长期
                if a.order != b.order { return a.order < b.order }
                return a.updatedAt > b.updatedAt
            }
        let upcoming = all
            .filter { !$0.pinned && $0.dueDate != nil && !$0.isPastAndCompleted() }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        let today = Calendar.current.startOfDay(for: Date())
        func snap(_ n: Note, _ section: TaskSection) -> TaskSnapshot {
            let p = n.checklistProgress
            let overdue: Bool = {
                guard let due = n.dueDate else { return false }
                return Calendar.current.startOfDay(for: due) < today && !n.isCompleted
            }()
            return TaskSnapshot(
                id: n.id,
                title: n.title.isEmpty ? "无标题" : n.title,
                isCompleted: n.isCompleted,
                section: section,
                longTerm: n.longTerm,
                checklistDone: p?.done ?? 0,
                checklistTotal: p?.total ?? 0,
                dueDate: n.dueDate,
                overdue: overdue
            )
        }

        // Cap the materialised list generously; the view slices per family.
        let tasks = pinned.prefix(10).map { snap($0, .pinned) }
                  + upcoming.prefix(10).map { snap($0, .upcoming) }

        return TasksEntry(
            date: .now,
            tasks: Array(tasks),
            pinnedTotal: pinned.count,
            upcomingTotal: upcoming.count
        )
    }
}

// MARK: - View

struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool { family == .accessoryRectangular }

    private var visibleCount: Int {
        switch family {
        case .systemSmall:          return 3
        case .systemMedium:         return 4
        case .systemLarge:          return 8
        case .accessoryRectangular: return 2
        default:                    return 3
        }
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    background
                }
            }
    }

    // Adaptive cyber backdrop + a soft pink→cyan glow in the top-trailing
    // corner so the card reads as "Doris" at a glance.
    private var background: some View {
        ZStack {
            CyberPalette.backdrop
            RadialGradient(
                colors: [CyberPalette.neonCyan.opacity(0.18), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 180
            )
            RadialGradient(
                colors: [CyberPalette.neonPink.opacity(0.14), .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 160
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if isAccessory {
            accessoryView
        } else if entry.tasks.isEmpty {
            emptyView
        } else {
            systemView
        }
    }

    // MARK: System (home-screen) layout

    private var systemView: some View {
        let visible = Array(entry.tasks.prefix(visibleCount))
        let pinnedRows = visible.filter { $0.section == .pinned }
        let upcomingRows = visible.filter { $0.section == .upcoming }
        let hidden = entry.total - visible.count
        let showHeaders = family != .systemSmall

        return VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            header

            if showHeaders {
                if !pinnedRows.isEmpty {
                    sectionLabel("置顶", tint: CyberPalette.neonPink)
                    ForEach(pinnedRows) { row($0) }
                }
                if !upcomingRows.isEmpty {
                    sectionLabel("日程", tint: CyberPalette.neonCyan)
                    ForEach(upcomingRows) { row($0) }
                }
            } else {
                ForEach(visible) { row($0) }
            }

            if hidden > 0 {
                Text("还有 \(hidden) 项")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 12 : 14)
        .padding(.vertical, family == .systemSmall ? 11 : 13)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CyberPalette.neonCyan)
            Text(family == .systemSmall ? "今日" : "Doris · 今日")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
            Spacer(minLength: 4)
            Text("\(entry.total)")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(CyberPalette.neonCyan)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(CyberPalette.neonCyan.opacity(0.16))
                )
        }
    }

    private func sectionLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .kerning(1.0)
            .foregroundStyle(tint)
            .padding(.top, 1)
    }

    @ViewBuilder
    private func row(_ t: TaskSnapshot) -> some View {
        HStack(spacing: 8) {
            // Section accent rail.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(t.isCompleted ? AnyShapeStyle(CyberPalette.doneAccent.opacity(0.4))
                                    : AnyShapeStyle(t.tint))
                .frame(width: 3)

            // Interactive checkbox — the one piece of capability parity.
            Button(intent: ToggleTaskIntent(noteID: t.id.uuidString)) {
                Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(t.isCompleted ? AnyShapeStyle(CyberPalette.doneAccent)
                                                   : AnyShapeStyle(t.tint))
            }
            .buttonStyle(.plain)

            Text(t.title)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .strikethrough(t.isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                .foregroundStyle(t.isCompleted
                    ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.42))
                    : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .lineLimit(1)

            Spacer(minLength: 4)

            trailingAccessory(t)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.001))   // keep row hit/visual rect stable
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(t.tint.opacity(t.isCompleted ? 0.0 : 0.06))
                )
        )
    }

    @ViewBuilder
    private func trailingAccessory(_ t: TaskSnapshot) -> some View {
        if t.checklistTotal > 0 {
            // Compact checklist progress pill with a thin fill bar.
            let frac = Double(t.checklistDone) / Double(max(t.checklistTotal, 1))
            HStack(spacing: 4) {
                Text("\(t.checklistDone)/\(t.checklistTotal)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(t.tint)
                Capsule()
                    .fill(t.tint.opacity(0.2))
                    .frame(width: 22, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(t.tint).frame(width: 22 * frac, height: 3)
                    }
            }
        } else if let due = t.dueDate {
            Text(due, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(t.overdue ? .red : .secondary)
        }
    }

    // MARK: Empty + accessory

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(CyberPalette.neonCyan)
            Text("全部完成")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text("没有置顶或今日任务")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "pin.fill").font(.caption2)
                Text("\(entry.total) 项待办").font(.caption2.weight(.semibold))
            }
            if let first = entry.tasks.first {
                Text(first.title).font(.caption2).lineLimit(1)
            }
            if entry.tasks.count > 1 {
                Text(entry.tasks[1].title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
