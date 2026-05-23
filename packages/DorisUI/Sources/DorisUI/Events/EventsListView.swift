import SwiftUI
import SwiftData
import DorisCore
import DorisIPC

/// Compact events panel used by the Mac anchor dropdown
/// (`NotchExpandedView`). Today's events render eagerly with the
/// source-kind filter chips applied; past days are surfaced via the
/// shared `DayCollapsibleEventList` and load on expand. Filter chips
/// only affect today — past-day sections show every active event for
/// that day so an expand is "what happened that day" rather than a
/// filtered subset.
public struct EventsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var filter: SourceKind?

    @Query private var todayMessages: [Message]

    public init() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let activeRaw = MessageState.active.rawValue
        _todayMessages = Query(
            filter: #Predicate<Message> { msg in
                msg.receivedAt >= startOfToday && msg.stateRaw == activeRaw
            },
            sort: [SortDescriptor(\Message.receivedAt, order: .reverse)]
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                FilterChip(label: L("All", "全部"), isOn: filter == nil) { filter = nil }
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    FilterChip(label: kind.displayName, isOn: filter == kind) { filter = kind }
                }
                Spacer()
            }
            .padding(8)
            Divider()
            ScrollView {
                // Anchor dropdown is short — only surface a week of
                // past days, otherwise the disclosure list extends past
                // the 400pt panel height and the user has to scroll
                // through empty days to reach today's events.
                DayCollapsibleEventList(
                    today: filteredToday,
                    pastDayCount: 7
                ) { msg in
                    EventsRowView(message: msg)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                msg.state = .dismissed
                            } label: {
                                Label(L("Dismiss", "忽略"), systemImage: "xmark")
                            }
                            Button {
                                msg.state = .actioned
                            } label: {
                                Label(L("Done", "完成"), systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                }
                .padding(12)
            }
        }
        .navigationTitle(L("Events", "事件"))
    }

    /// Today's messages with the source-kind filter chip applied (if
    /// any). When the chip is "All", returns the @Query result
    /// untouched. The filter intentionally only narrows today — past
    /// days remain a full "what happened" archive.
    private var filteredToday: [Message] {
        guard let f = filter else { return todayMessages }
        return todayMessages.filter { $0.source == f }
    }
}

private struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
