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

/// Home-screen "今日" widget: pinned (置顶 + 长期) plus what is due today
/// or overdue (日程), with tap-to-complete checkboxes and checklist
/// progress. Anything dated after today is reduced to a "之后 N 项" count.
/// Same rule as the macOS desktop card (DesktopPanelView); the main Today
/// screens keep the full look-ahead, having the room for it.
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
    case due        // 日程 — due today, or overdue
    case later      // 之后 — the next few days, only in space left over
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
    let dueToday: Bool
    let overdue: Bool

    /// Section/long-term accent used for the rail + empty checkbox.
    var tint: Color {
        switch section {
        case .pinned: return longTerm ? CyberPalette.longTermViolet : CyberPalette.neonPink
        case .due:    return CyberPalette.neonCyan
        case .later:  return CyberPalette.neonCyan.opacity(0.5)
        }
    }
}

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskSnapshot]
    /// Rows the widget could list (pinned + due), finished ones included —
    /// what the "+N 更多" overflow is measured against.
    let listedTotal: Int
    /// Unfinished among those. The hero number: finished rows stay on the
    /// card, struck through, but they aren't "待办".
    let openCount: Int
    /// Unfinished tasks due in the next `laterHorizonDays` days, soonest
    /// first. Listed only in space today's rows leave empty, below a
    /// "之后" rule — today always comes first.
    let later: [TaskSnapshot]
    /// Every unfinished task dated after today, however far out. The
    /// "之后还有 N 项" count is measured against this.
    let laterTotal: Int

    static func empty(_ date: Date = .now) -> TasksEntry {
        TasksEntry(date: date, tasks: [], listedTotal: 0, openCount: 0, later: [], laterTotal: 0)
    }
}

// `长期` violet — kept local so the widget needn't reach into app code.
private extension CyberPalette {
    static let longTermViolet = Color(red: 0.62, green: 0.51, blue: 1.0)
}

// MARK: - Provider

struct TasksProvider: TimelineProvider {
    /// How far ahead the leftover-space "之后" section looks.
    static let laterHorizonDays = 7

    func placeholder(in context: Context) -> TasksEntry {
        .empty()
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(load(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        // Hourly as a floor (WidgetKit also reloads on the toggle intent and
        // app foreground), but never later than midnight: what counts as
        // "today" is now the whole point of the card, so tomorrow's tasks
        // must move in on the stroke of the day rather than up to an hour
        // after it.
        let now = Date()
        let cal = Calendar.current
        let hour = now.addingTimeInterval(60 * 60)
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? hour
        completion(Timeline(entries: [load(now: now)], policy: .after(min(hour, midnight))))
    }

    private func load(now: Date) -> TasksEntry {
        // useCloudKit: false — read the local App-Group SQLite directly.
        // Standing up NSPersistentCloudKitContainer inside a widget extension
        // blows the CPU budget, can't finish a fetch before iOS suspends, and
        // traps on unsigned builds. The app owns the CloudKit mirror + keeps
        // the SQLite fresh; the widget piggybacks + is reloaded on app
        // sync/foreground (see SyncTimer.poke / applicationDidBecomeActive).
        guard let container = try? ModelContainerFactory.make(useCloudKit: false) else {
            return .empty(now)
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
        let dated = all
            .filter { !$0.pinned && $0.dueDate != nil && !$0.isPastAndCompleted(now: now) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let due = dated.filter { !$0.isDueAfterToday(now: now) }
        // Later: unfinished only (a struck-through task next week is noise
        // on a glance card), and only this coming week — further out it's
        // just a count.
        let upcoming = dated.filter { $0.isDueAfterToday(now: now) && !$0.isCompleted }
        let cal = Calendar.current
        let horizon = cal.date(byAdding: .day, value: Self.laterHorizonDays + 1,
                               to: cal.startOfDay(for: now)) ?? now
        let soon = upcoming.filter { ($0.dueDate ?? .distantFuture) < horizon }

        func snap(_ n: Note, _ section: TaskSection) -> TaskSnapshot {
            let p = n.checklistProgress
            return TaskSnapshot(
                id: n.id,
                title: n.title.isEmpty ? "无标题" : n.title,
                isCompleted: n.isCompleted,
                section: section,
                longTerm: n.longTerm,
                checklistDone: p?.done ?? 0,
                checklistTotal: p?.total ?? 0,
                dueDate: n.dueDate,
                dueToday: n.isDueToday(now: now),
                overdue: n.isOverdue(now: now)
            )
        }

        // Cap the materialised list generously; the view slices per family.
        let tasks = pinned.prefix(10).map { snap($0, .pinned) }
                  + due.prefix(10).map { snap($0, .due) }

        return TasksEntry(
            date: now,
            tasks: Array(tasks),
            listedTotal: pinned.count + due.count,
            openCount: (pinned + due).filter { !$0.isCompleted }.count,
            later: soon.prefix(8).map { snap($0, .later) },
            laterTotal: upcoming.count
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
//  What the widget lists is decided above, in TasksProvider; this layer only
//  lays it out. Targets iOS 18 WidgetKit.
// ============================================================================

// MARK: - View

struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool { family == .accessoryRectangular }

    // MARK: Layout plan
    //
    // What fits is decided by height, not a fixed row count. The counts used
    // to be 3 / 4 / 8, and the medium card couldn't hold four rows plus
    // section captions and the footer: the last rows ran past its bottom
    // edge and vanished without being counted in "+N 更多". Heights below
    // are measured from the rendered card (rows include their hairline).

    private struct Metrics {
        let chrome: CGFloat        // vertical padding + hero line + rule + list top gap
        let row: CGFloat
        let caption: CGFloat       // a 置顶 / 日程 caption
        let laterRule: CGFloat     // the 之后 rule, with its top gap
        let laterRow: CGFloat      // upcoming rows are set tighter than today's
        let nothingToday: CGFloat
        let footer: CGFloat
    }

    private var metrics: Metrics {
        family == .systemSmall
            ? Metrics(chrome: 24 + 30 + 5, row: 27.6, caption: 0, laterRule: 0, laterRow: 0,
                      nothingToday: 25, footer: 17)
            : Metrics(chrome: 28 + 34.4 + 7, row: 29.6, caption: 14, laterRule: 15, laterRow: 23,
                      nothingToday: 25, footer: 17)
    }

    private struct Plan {
        var today: [TaskSnapshot] = []
        var later: [TaskSnapshot] = []
        var captions = false
        /// Extra space around the 之后 rule, taken from whatever height is
        /// left once everything is placed. Set tight, the two sections ran
        /// together on the large card while its bottom third sat empty; on
        /// medium there's nothing spare, so it stays tight there.
        var gapAboveRule: CGFloat = 0
        var gapBelowRule: CGFloat = 0
    }

    /// Today first — pinned, then due / overdue — for as long as they fit.
    /// Only when *all* of today fits does the rest go to the days ahead,
    /// and only if at least two of those fit under the 之后 rule (a lone
    /// row there reads as clutter). When that is short by the captions'
    /// height, the captions give way: the rule already marks the boundary.
    private func plan(height: CGFloat) -> Plan {
        let m = metrics
        // The footer is always budgeted; it may spill ~2pt into the bottom
        // padding, which the eye can't tell from padding.
        let full = height - m.chrome - m.footer + 2
        func fillToday(captions: Bool) -> (rows: [TaskSnapshot], left: CGFloat, sections: Set<TaskSection>) {
            var b = full, rows: [TaskSnapshot] = [], seen = Set<TaskSection>()
            for t in entry.tasks {
                let cost = m.row + (captions && !seen.contains(t.section) ? m.caption : 0)
                guard cost <= b else { break }
                b -= cost; seen.insert(t.section); rows.append(t)
            }
            return (rows, b, seen)
        }
        // Captions are a nicety; another task row is worth more.
        var fill = fillToday(captions: family != .systemSmall)
        var p = Plan(captions: family != .systemSmall)
        if p.captions {
            let bare = fillToday(captions: false)
            if bare.rows.count > fill.rows.count { fill = bare; p.captions = false }
        }
        p.today = fill.rows
        var budget = fill.left
        let sections = fill.sections
        guard family == .systemMedium || family == .systemLarge,
              p.today.count == entry.tasks.count, !entry.later.isEmpty else { return p }
        if p.today.isEmpty { budget -= m.nothingToday }
        func fits(_ b: CGFloat) -> Int { max(0, Int(((b - m.laterRule) / m.laterRow).rounded(.down))) }
        var n = fits(budget)
        if n < 2, p.captions, !sections.isEmpty {
            let freed = CGFloat(sections.count) * m.caption
            let without = fits(budget + freed)
            if without >= 2 { p.captions = false; n = without; budget += freed }
        }
        if n >= 2 {
            p.later = Array(entry.later.prefix(n))
            let spare = budget - m.laterRule - CGFloat(p.later.count) * m.laterRow
            p.gapAboveRule = min(12, max(0, spare))
            p.gapBelowRule = min(4, max(0, spare - p.gapAboveRule))
        }
        return p
    }

    // Cached so we don't allocate a DateFormatter every render.
    private static let heroDateFormatterFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f
    }()
    private static let laterDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE M/d"
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
        } else {
            GeometryReader { geo in
                let p = plan(height: geo.size.height)
                if entry.tasks.isEmpty && p.later.isEmpty {
                    emptyView
                } else {
                    systemView(p)
                }
            }
        }
    }

    // MARK: System (home-screen) layout

    private func systemView(_ p: Plan) -> some View {
        let visible = p.today
        let pinnedRows = visible.filter { $0.section == .pinned }
        let dueRows = visible.filter { $0.section == .due }
        let showCaptions = p.captions
        // With nothing for today, a one-line note stands in for the list so
        // the later rows can't be mistaken for today's.
        let later = p.later

        return VStack(alignment: .leading, spacing: 0) {
            heroLine
            divider.padding(.top, family == .systemSmall ? 6 : 8)

            VStack(alignment: .leading, spacing: 0) {
                if showCaptions {
                    if !pinnedRows.isEmpty {
                        sectionCaption("置顶", tint: CyberPalette.neonPink)
                        rowStack(pinnedRows)
                    }
                    if !dueRows.isEmpty {
                        sectionCaption("日程", tint: CyberPalette.neonCyan)
                            .padding(.top, pinnedRows.isEmpty ? 0 : 4)
                        rowStack(dueRows)
                    }
                } else {
                    rowStack(visible)
                }
                if visible.isEmpty {
                    nothingTodayLine
                }
                if !later.isEmpty {
                    laterRule
                        .padding(.top, (visible.isEmpty ? 2 : 4) + p.gapAboveRule)
                        .padding(.bottom, p.gapBelowRule)
                    rowStack(later)
                }
            }
            .padding(.top, family == .systemSmall ? 5 : 7)

            if let footer = footerText(shown: visible.count, laterShown: later.count) {
                Text(footer)
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

    /// The boundary between today and the days ahead: a labelled hairline,
    /// so the later rows can't be read as more of today.
    private var laterRule: some View {
        HStack(spacing: 6) {
            Rectangle().fill(HierarchicalShapeStyle.primary.opacity(0.14)).frame(height: 0.5)
            Text("之后")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle().fill(HierarchicalShapeStyle.primary.opacity(0.14)).frame(height: 0.5)
        }
        .padding(.bottom, 1)
    }

    private var nothingTodayLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.85))
            Text("今天没有待办")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    /// One quiet trailing line for everything the card doesn't list:
    /// today's overflow ("+2 更多") and whatever of the days ahead didn't
    /// fit ("之后还有 3 项"). Tapping opens the app, which has it all.
    private func footerText(shown: Int, laterShown: Int) -> String? {
        var parts: [String] = []
        let hidden = entry.listedTotal - shown
        if hidden > 0 { parts.append("+\(hidden) 更多") }
        let laterLeft = entry.laterTotal - laterShown
        if laterLeft > 0 { parts.append(laterShown > 0 ? "之后还有 \(laterLeft) 项" : "之后 \(laterLeft) 项") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Hero

    // The single loudest element on the card: count + label, date trailing.
    private var heroLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(entry.openCount)")
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
                    .font(.system(size: t.section == .later ? 13 : 15, weight: .regular))
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
                .font(.system(size: t.section == .later ? 12 : 13, weight: .regular, design: .rounded))
                .strikethrough(t.isCompleted, color: CyberPalette.doneAccent.opacity(0.8))
                .foregroundStyle(t.isCompleted
                    ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.4))
                    : t.section == .later
                        // Upcoming rows step back so today's lead.
                        ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                        : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .lineLimit(1)

            Spacer(minLength: 4)

            trailingAccessory(t)
        }
        // Upcoming rows are set tighter: they're a glance ahead, and the
        // medium card can only fit two of them this way.
        .padding(.vertical, t.section == .later ? 3.5 : (family == .systemSmall ? 5 : 6))
    }

    /// Same rule as the macOS card: checklist progress when there is one,
    /// the date only when it isn't today (red if overdue). These used to
    /// share one slot, so a task with sub-tasks never showed its date and
    /// an overdue one never turned red. Small is too narrow for both, so
    /// it keeps whichever matters more: an overdue date, else progress.
    @ViewBuilder
    private func trailingAccessory(_ t: TaskSnapshot) -> some View {
        let hasRing = t.checklistTotal > 0
        let hasDate = t.dueDate != nil && !t.dueToday
        let compact = family == .systemSmall
        let showRing = hasRing && !(compact && hasDate && t.overdue)
        let showDate = hasDate && !(compact && showRing)
        HStack(spacing: 5) {
            if showRing {
                // Graft (1): checklist progress as a 16pt ring + micro count —
                // more elegant and legible at widget scale than a 3px bar.
                let frac = Double(t.checklistDone) / Double(max(t.checklistTotal, 1))
                let ringTint = (t.checklistDone >= t.checklistTotal)
                    ? CyberPalette.doneAccent : t.tint
                Text("\(t.checklistDone)/\(t.checklistTotal)")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                progressRing(fraction: frac, tint: ringTint)
            }
            if showDate, let due = t.dueDate {
                // Upcoming rows name the weekday ("周六 10/3") — within a
                // week, the day is what you actually plan around.
                Text(t.section == .later
                     ? Self.laterDateFormatter.string(from: due)
                     : due.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(t.overdue ? AnyShapeStyle(CyberPalette.overdueAccent) : AnyShapeStyle(.secondary))
            }
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
            if entry.laterTotal > 0 {
                Text("之后 \(entry.laterTotal) 项")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 3)
            }
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
                Text("\(entry.openCount) 件待办").font(.caption2.weight(.semibold))
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
