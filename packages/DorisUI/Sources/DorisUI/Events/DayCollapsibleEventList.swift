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

    /// Per-past-day event counts (loaded eagerly via `fetchCount`, much
    /// cheaper than materialising rows). Drives two things:
    /// 1. **Skip empty days entirely** — no point rendering a
    ///    DisclosureGroup for a date with zero events. Earlier the
    ///    list always showed every day in the window as a collapsed
    ///    row even if it was empty, which read as visual noise.
    /// 2. Section-header count badge — shows immediately instead of
    ///    waiting for the user to expand the row.
    /// Loaded once on appear (via `.task` in pastDaysSection); changes
    /// to today's events still trigger via the `today` array but past
    /// counts stay anchored to whatever was true at appear time.
    @State private var dayCounts: [Date: Int] = [:]
    @State private var dayCountsLoaded = false

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

    /// Past days within the window that actually have ≥1 active event.
    /// Empty until `dayCountsLoaded`, so the section briefly shows
    /// nothing on first appear instead of flashing 14 placeholder
    /// rows that then collapse. The flash window is the duration of
    /// one batch of `fetchCount` calls (≤100 ms on a normal store).
    private var nonEmptyPastDays: [Date] {
        guard dayCountsLoaded else { return [] }
        return pastDays.filter { (dayCounts[$0] ?? 0) > 0 }
    }

    private var pastDaysSection: some View {
        // Only render the section + top-padding when there's something
        // to show. An entirely-empty past window (e.g. fresh install,
        // or all old days settled) results in zero chrome below
        // today — no shelf, no separator, nothing wasted.
        let days = nonEmptyPastDays
        return Group {
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        pastDaySection(day: day)
                    }
                }
                .padding(.top, 8)
            }
        }
        // Attach the count load to the wrapper so it fires regardless
        // of which branch renders. Idempotent — guarded by
        // `dayCountsLoaded` inside the function.
        .task { await loadDayCounts() }
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
                // Use the eagerly-loaded fetchCount; falling back to
                // the materialised count only if (somehow) the count
                // probe missed this day. Means the count badge
                // displays as soon as the row appears, no waiting for
                // expand.
                count: dayCounts[day] ?? loadedDays[day]?.count,
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

    /// Up-front cheap count probe — fetchCount per past day so empty
    /// days can be skipped entirely from the rendered list. Way
    /// lighter than materialising rows: `fetchCount` issues a
    /// `SELECT COUNT(*)` against the SQLite store, no object
    /// instantiation. 14 of these typically come back under 50ms.
    /// Idempotent — guarded by `dayCountsLoaded` so re-renders don't
    /// re-fetch.
    @MainActor
    private func loadDayCounts() async {
        guard !dayCountsLoaded else { return }
        let cal = Calendar.current
        let activeRaw = MessageState.active.rawValue
        var counts: [Date: Int] = [:]
        for day in pastDays {
            let start = cal.startOfDay(for: day)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
            let desc = FetchDescriptor<Message>(
                predicate: #Predicate<Message> { msg in
                    msg.receivedAt >= start
                        && msg.receivedAt < end
                        && msg.stateRaw == activeRaw
                }
            )
            counts[day] = (try? ctx.fetchCount(desc)) ?? 0
        }
        dayCounts = counts
        dayCountsLoaded = true
    }

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
