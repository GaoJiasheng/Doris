import SwiftUI
import SwiftData
import DorisCore
import DorisIPC
import DorisUI

/// Events tab — list of Messages received via CloudKit / local insertion,
/// rendered as cyber-themed cards. Mirrors the Mac AnchorEventsView but
/// vertically scrollable for a phone form factor.
///
/// Pull-to-refresh fires `AppCommands.syncNow` (manual sync) so the user
/// can force a CloudKit poke without going to Settings.
struct EventsScreen: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx

    /// Only today's active events are fetched eagerly. Past days are
    /// rendered as collapsed sections by `DayCollapsibleEventList` and
    /// their messages load on first expand. This keeps the tab snappy
    /// — earlier full-history `@Query` was the main culprit behind the
    /// "events tab takes a second to paint" complaint.
    @Query private var todayMessages: [Message]

    init() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let activeRaw = MessageState.active.rawValue
        _todayMessages = Query(
            filter: #Predicate<Message> { msg in
                msg.receivedAt >= startOfToday && msg.stateRaw == activeRaw
            },
            sort: [SortDescriptor(\Message.receivedAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if todayMessages.isEmpty && !hasAnyMessage {
                    emptyState
                        .padding(.top, 80)
                } else {
                    DayCollapsibleEventList(today: todayMessages) { m in
                        EventRow(message: m)
                            .contextMenu {
                                Button {
                                    m.state = .actioned
                                    try? ctx.save()
                                } label: {
                                    Label(L("Mark done", "标为已读"), systemImage: "checkmark.circle")
                                }
                                Button {
                                    m.state = .dismissed
                                    try? ctx.save()
                                } label: {
                                    Label(L("Dismiss", "忽略"), systemImage: "xmark.circle")
                                }
                                Button(role: .destructive) {
                                    ctx.delete(m)
                                    try? ctx.save()
                                } label: {
                                    Label(L("Delete", "删除"), systemImage: "trash")
                                }
                            }
                    }
                    .padding(14)
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                // Run the same hook the Settings "Sync Now" button uses.
                // Fire-and-forget into the AppDelegate — the sync timer
                // pokes synchronously on the main actor and updates
                // `SyncSettings.lastSyncedAt`, so the UI just observes.
                AppCommands.syncNow()
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            .navigationTitle(L("Events", "事件"))
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// Cheap guard: if today is empty AND there are zero messages ever,
    /// show the "no events yet" empty state instead of a list of empty
    /// collapsed days. We bail to a fetchCount probe so we don't
    /// reintroduce a full-history `@Query` just for this UX hint.
    private var hasAnyMessage: Bool {
        var desc = FetchDescriptor<Message>()
        desc.fetchLimit = 1
        let count = (try? ctx.fetchCount(desc)) ?? 0
        return count > 0
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(.primary.opacity(0.4))
            Text(L("No events yet", "暂无事件"))
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.65))
            Text(L("Pull down to sync now.", "下拉以立即同步。"))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.45))
        }
    }
}

private struct EventRow: View {
    let message: Message

    var body: some View {
        let levelTint = EventLevelStyle.color(for: message.level)
        CyberCard {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(levelTint)
                    .frame(width: 3)
                    .opacity(message.level == .info ? 0.35 : 1.0)
                Image(systemName: message.iconName ?? message.source.sfSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(message.level == .info
                                     ? AnyShapeStyle(CyberPalette.neonCyan)
                                     : AnyShapeStyle(levelTint))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(message.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if message.level != .info {
                            Image(systemName: message.level.sfSymbol)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(levelTint)
                        }
                    }
                    if let body = message.bodyMarkdown, !body.isEmpty {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.65))
                            .lineLimit(3)
                    }
                    // Absolute timestamp; see EventsRowView for
                    // rationale (relative time was hard to scan).
                    Text(message.receivedAt,
                         format: .dateTime.month(.twoDigits).day(.twoDigits)
                                          .hour(.twoDigits(amPM: .omitted))
                                          .minute(.twoDigits))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}
