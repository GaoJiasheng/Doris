import SwiftUI
import SwiftData
import DorisCore
import DorisIPC

/// Day-grouped events container shared by the Mac anchor dropdown, Mac
/// main window, and iOS Events tab. Default behaviour:
///
/// - **Today section** is rendered eagerly. Caller passes the messages
///   in via `today:` (presumably from a `@Query` predicated to
///   `receivedAt >= startOfToday`) so SwiftData only materialises that
///   slice on view appearance — keeping the initial paint cheap.
/// - **Past N days** are rendered as collapsed `DisclosureGroup` rows.
///   Each row's body is fetched lazily via the model context the first
///   time the user expands it, then cached in @State so subsequent
///   collapse/expand cycles are instant.
/// - Empty past days still show in the list with a `0` count and an
///   "暂无事件" placeholder when expanded — keeps the UI structure
///   stable & makes "did anything happen yesterday?" trivially
///   answerable without a content-presence guess.
///
/// The caller supplies a `rowBuilder` so the visual treatment of each
/// row (icon, stripe, body markdown rendering) stays owned by the host
/// surface — only the date grouping & lazy load logic is shared.
public struct DayCollapsibleEventList<Row: View>: View {
    /// Today's already-fetched messages. Caller is responsible for the
    /// `@Query`: `receivedAt >= startOfToday && stateRaw == "active"`.
    public let today: [Message]
    /// How many past days to surface as collapsible sections. 14 keeps
    /// the list comfortable on a phone without blowing up the picker
    /// height; callers can shrink for narrower surfaces (anchor
    /// dropdown uses 7).
    public let pastDayCount: Int
    /// Row visual — owned by the host so the anchor/main-window/iOS
    /// surfaces can keep their distinctive event-row treatments.
    public let rowBuilder: (Message) -> Row
    /// Padding between rows. Matches host's spacing convention.
    public let rowSpacing: CGFloat

    @Environment(\.modelContext) private var ctx
    @ObservedObject private var lang = LanguageSettings.shared

    /// Per-day cache. `nil` ⇒ never loaded; `[]` ⇒ loaded, no events;
    /// `[m, ...]` ⇒ loaded with content. Keyed by the day's start-of-day
    /// Date so we round-trip cleanly through Calendar.
    @State private var loadedDays: [Date: [Message]] = [:]
    @State private var expandedDays: Set<Date> = []

    public init(
        today: [Message],
        pastDayCount: Int = 14,
        rowSpacing: CGFloat = 8,
        @ViewBuilder row: @escaping (Message) -> Row
    ) {
        self.today = today
        self.pastDayCount = pastDayCount
        self.rowSpacing = rowSpacing
        self.rowBuilder = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            todaySection
            pastDaysSection
        }
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            sectionHeader(
                title: L("Today", "今天"),
                count: today.count,
                isToday: true
            )
            if today.isEmpty {
                Text(L("No events today.", "今天暂无事件。"))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.5))
                    .padding(.vertical, 4)
            } else {
                ForEach(today) { msg in
                    rowBuilder(msg)
                }
            }
        }
    }

    // MARK: - Past days

    private var pastDays: [Date] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        return (1...pastDayCount).compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: startOfToday)
        }
    }

    private var pastDaysSection: some View {
        // Indented spacing so past-day sections feel like an archive
        // shelf below "today", not a parallel surface.
        VStack(alignment: .leading, spacing: 4) {
            ForEach(pastDays, id: \.self) { day in
                pastDaySection(day: day)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func pastDaySection(day: Date) -> some View {
        let isExpanded = expandedDays.contains(day)
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedDays.contains(day) },
                set: { wantExpanded in
                    if wantExpanded {
                        expandedDays.insert(day)
                    } else {
                        expandedDays.remove(day)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                if let cached = loadedDays[day] {
                    if cached.isEmpty {
                        Text(L("No events.", "暂无事件。"))
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.5))
                            .padding(.vertical, 4)
                    } else {
                        ForEach(cached) { msg in
                            rowBuilder(msg)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("Loading…", "加载中…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .task(id: day) {
                        await loadDay(day)
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.top, 4)
        } label: {
            sectionHeader(
                title: dayLabel(for: day),
                count: loadedDays[day]?.count,
                isToday: false,
                isExpanded: isExpanded
            )
        }
        // SwiftUI's default DisclosureGroup chevron color is dim; lift
        // it slightly so past-day rows are still tappable-looking on
        // dark cyber backgrounds without dominating the today section.
        .tint(.primary.opacity(0.55))
    }

    // MARK: - Lazy fetch

    /// Fire the SwiftData fetch for a single day. Caches result in
    /// `loadedDays` so toggling the disclosure doesn't refetch. Filters
    /// out non-active states so dismissed/actioned events don't bloat
    /// historical sections.
    @MainActor
    private func loadDay(_ day: Date) async {
        // Guard against repeat firing if `.task` re-runs (e.g. day
        // identity changes are rare but `.task(id:)` is defensive).
        guard loadedDays[day] == nil else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            loadedDays[day] = []
            return
        }
        // SwiftData #Predicate doesn't access computed properties, so
        // compare the raw state String directly.
        let activeRaw = MessageState.active.rawValue
        var descriptor = FetchDescriptor<Message>(
            predicate: #Predicate<Message> { msg in
                msg.receivedAt >= start
                    && msg.receivedAt < end
                    && msg.stateRaw == activeRaw
            },
            sortBy: [SortDescriptor(\Message.receivedAt, order: .reverse)]
        )
        // Day caps at a generous limit so the rendering cost of a busy
        // backfill day is bounded; rare for production but keeps the
        // UI from stalling if a CloudKit replay dumps thousands of
        // events on a single timestamp range.
        descriptor.fetchLimit = 500
        let fetched = (try? ctx.fetch(descriptor)) ?? []
        loadedDays[day] = fetched
    }

    // MARK: - Header chrome

    private func sectionHeader(
        title: String,
        count: Int?,
        isToday: Bool,
        isExpanded: Bool = true
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: isToday ? 13 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isToday
                    ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                    : AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.78)))
            if let c = count {
                Text("\(c)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.55))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(.primary.opacity(0.08))
                    )
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func dayLabel(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInYesterday(day) {
            return L("Yesterday", "昨天")
        }
        let daysAgo = cal.dateComponents([.day], from: day, to: cal.startOfDay(for: Date())).day ?? 0
        if daysAgo < 7 {
            // Inside this week — render as weekday name (周X / Wed)
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }
}
