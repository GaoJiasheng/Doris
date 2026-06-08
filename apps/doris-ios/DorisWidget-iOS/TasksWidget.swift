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
              let container = try? ModelContainerFactory.make(useCloudKit: false) else {
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
        // useCloudKit: false — read the local App-Group SQLite directly.
        // Standing up NSPersistentCloudKitContainer inside a widget extension
        // blows the CPU budget, can't finish a fetch before iOS suspends, and
        // traps on unsigned builds. The app owns the CloudKit mirror + keeps
        // the SQLite fresh; the widget piggybacks + is reloaded on app
        // sync/foreground (see SyncTimer.poke / applicationDidBecomeActive).
        guard let container = try? ModelContainerFactory.make(useCloudKit: false) else {
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

// ============================================================================
//  TasksWidget.swift — VIEW LAYER ONLY.
//  Final redesign: "Calm Focus" (hero ledger header + hairline-divided calm
//  list with quiet accent dots) + grafts from "Glassy Depth":
//    • 16pt progress ring in place of the capsule bar
//    • 4pt "LED" tint dot on section captions (colorblind-friendly)
//    • rebuilt accessoryRectangular with per-row state glyphs + overdue mark
//
//  Drop-in replacement for `struct TasksWidgetView` and its private helpers
//  (the original lines 184–399). Everything above line 182 — TasksProvider,
//  TaskSnapshot, TasksEntry, ToggleTaskIntent, TasksWidget, and the private
//  `CyberPalette.longTermViolet` extension — stays EXACTLY as-is.
//  Targets iOS 18 WidgetKit.
// ============================================================================

// MARK: - View

struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool { family == .accessoryRectangular }

    // One fewer row than the original on small to buy breathing room for the
    // hero line; medium/large unchanged.
    private var visibleCount: Int {
        switch family {
        case .systemSmall:          return 3
        case .systemMedium:         return 4
        case .systemLarge:          return 8
        case .accessoryRectangular: return 2
        default:                    return 3
        }
    }

    // Cached so we don't allocate a DateFormatter every render.
    private static let heroDateFormatterFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f
    }()
    private static let heroDateFormatterShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f
    }()

    // MARK: Body

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory { Color.clear } else { background }
            }
    }

    // Single soft diagonal pink→cyan sheen — neon as ambient atmosphere, not
    // two competing spotlights. Additive over the dark backdrop.
    private var background: some View {
        ZStack {
            CyberPalette.backdrop
            LinearGradient(
                colors: [
                    CyberPalette.neonPink.opacity(0.10),
                    .clear,
                    CyberPalette.neonCyan.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
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
        let showCaptions = family != .systemSmall

        return VStack(alignment: .leading, spacing: 0) {
            heroLine
            divider.padding(.top, family == .systemSmall ? 6 : 8)

            VStack(alignment: .leading, spacing: 0) {
                if showCaptions {
                    if !pinnedRows.isEmpty {
                        sectionCaption("置顶", tint: CyberPalette.neonPink)
                        rowStack(pinnedRows)
                    }
                    if !upcomingRows.isEmpty {
                        sectionCaption("日程", tint: CyberPalette.neonCyan)
                            .padding(.top, pinnedRows.isEmpty ? 0 : 4)
                        rowStack(upcomingRows)
                    }
                } else {
                    rowStack(visible)
                }
            }
            .padding(.top, family == .systemSmall ? 5 : 7)

            if hidden > 0 {
                Text("+\(hidden) 更多")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 13 : 15)
        .padding(.vertical, family == .systemSmall ? 12 : 14)
    }

    // Rows share one VStack so the inter-row hairlines are uniform.
    @ViewBuilder
    private func rowStack(_ rows: [TaskSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, t in
                if idx > 0 { divider }
                row(t)
            }
        }
    }

    // MARK: Hero

    // The single loudest element on the card: count + label, date trailing.
    private var heroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(entry.total)")
                .font(.system(size: family == .systemSmall ? 19 : 22,
                              weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(CyberPalette.neonCyan)
            Text("件待办")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(dateLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private var dateLabel: String {
        let f = family == .systemSmall
            ? Self.heroDateFormatterShort
            : Self.heroDateFormatterFull
        return f.string(from: entry.date)
    }

    // The one structural line in the design.
    private var divider: some View {
        Rectangle()
            .fill(HierarchicalShapeStyle.primary.opacity(0.08))
            .frame(height: 0.5)
    }

    // Graft (2): a 4pt "LED" tint dot prefix makes 置顶/日程 scannable without
    // relying on color alone — colorblind-friendly at near-zero visual cost.
    private func sectionCaption(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint.opacity(0.85))
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tint.opacity(0.7))
        }
        .padding(.bottom, 2)
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ t: TaskSnapshot) -> some View {
        HStack(spacing: 8) {
            // Interactive checkbox — capability parity, behaviour unchanged.
            Button(intent: ToggleTaskIntent(noteID: t.id.uuidString)) {
                Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(t.isCompleted
                        ? AnyShapeStyle(CyberPalette.doneAccent)
                        : AnyShapeStyle(t.tint.opacity(0.85)))
            }
            .buttonStyle(.plain)

            // Quiet bucket signal: a small accent dot, not a slab rail.
            Circle()
                .fill(t.isCompleted
                    ? AnyShapeStyle(CyberPalette.doneAccent.opacity(0.35))
                    : AnyShapeStyle(t.tint))
                .frame(width: 5, height: 5)

            Text(t.title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .strikethrough(t.isCompleted, color: CyberPalette.doneAccent.opacity(0.8))
                .foregroundStyle(t.isCompleted
                    ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.4))
                    : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .lineLimit(1)

            Spacer(minLength: 4)

            trailingAccessory(t)
        }
        .padding(.vertical, family == .systemSmall ? 5 : 6)
    }

    @ViewBuilder
    private func trailingAccessory(_ t: TaskSnapshot) -> some View {
        if t.checklistTotal > 0 {
            // Graft (1): checklist progress as a 16pt ring + micro count —
            // more elegant and legible at widget scale than a 3px bar.
            let frac = Double(t.checklistDone) / Double(max(t.checklistTotal, 1))
            let ringTint = (t.checklistDone >= t.checklistTotal)
                ? CyberPalette.doneAccent : t.tint
            HStack(spacing: 5) {
                Text("\(t.checklistDone)/\(t.checklistTotal)")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                progressRing(fraction: frac, tint: ringTint)
            }
        } else if let due = t.dueDate {
            Text(due, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(t.overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
        }
    }

    // 16pt progress ring: track + trimmed arc swept from 12 o'clock; the
    // arc fills to doneAccent when the checklist completes.
    private func progressRing(fraction: Double, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.0001, min(fraction, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }

    // MARK: Empty (same grammar as the populated card, at rest)

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroLine
            divider.padding(.top, family == .systemSmall ? 6 : 8)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(CyberPalette.neonCyan.opacity(0.85))
                Text("今天没有待办")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemSmall ? 13 : 15)
        .padding(.vertical, family == .systemSmall ? 12 : 14)
    }

    // MARK: Lock-screen accessory (rebuilt — graft 3, vibrancy-safe)

    // Per-row circle/checkmark state glyph + overdue "!" marker; only
    // .primary/.secondary foregrounds + SF Symbols so the system recolors
    // it cleanly under any wallpaper tint. No brand colors leak in.
    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checklist").font(.caption2)
                Text("\(entry.total) 件待办").font(.caption2.weight(.semibold))
            }
            ForEach(Array(entry.tasks.prefix(2).enumerated()), id: \.element.id) { idx, t in
                HStack(spacing: 4) {
                    Image(systemName: t.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text(t.title)
                        .font(.caption2)
                        .lineLimit(1)
                        .strikethrough(t.isCompleted)
                    if t.overdue {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 8, weight: .black))
                    }
                }
                .foregroundStyle(idx == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
