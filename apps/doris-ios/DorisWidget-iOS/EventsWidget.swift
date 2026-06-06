import WidgetKit
import SwiftUI
import SwiftData
import DorisCore
import DorisUI

struct EventsWidget: Widget {
    let kind: String = "com.gavin.doris.widget.events"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EventsProvider()) { entry in
            EventsWidgetView(entry: entry)
        }
        .configurationDisplayName("Doris Events")
        .description("Recent events.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct EventsEntry: TimelineEntry {
    let date: Date
    let messages: [EventsSnapshot]
}

struct EventsSnapshot: Identifiable {
    let id: UUID
    let title: String
    let source: String
    let receivedAt: Date
}

struct EventsProvider: TimelineProvider {
    func placeholder(in context: Context) -> EventsEntry {
        EventsEntry(date: .now, messages: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (EventsEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EventsEntry>) -> Void) {
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [load()], policy: .after(next)))
    }

    /// Read directly from the local SQLite store shared via the App
    /// Group. Critical that this is `useCloudKit: false`:
    ///   · The main app owns the CloudKit mirror — it keeps the SQLite
    ///     file fresh. The widget piggybacks on whatever the app last
    ///     synced.
    ///   · `useCloudKit: true` in a widget extension means iOS has to
    ///     stand up an `NSPersistentCloudKitContainer` inside the
    ///     widget process every timeline tick. That blows past the
    ///     widget's tight CPU/time budget and on unsigned dev builds
    ///     traps the process (same brk 1 we hit in the main app).
    ///   · The widget process is short-lived. There's no time for a
    ///     CloudKit fetch to actually complete before iOS suspends us.
    private func load() -> EventsEntry {
        guard let container = try? ModelContainerFactory.make(useCloudKit: false) else {
            return EventsEntry(date: .now, messages: [])
        }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Message>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        let messages = (try? context.fetch(descriptor)) ?? []
        return EventsEntry(
            date: .now,
            messages: messages.map {
                EventsSnapshot(id: $0.id, title: $0.title, source: $0.source.displayName, receivedAt: $0.receivedAt)
            }
        )
    }
}

struct EventsWidgetView: View {
    let entry: EventsEntry

    var body: some View {
        if entry.messages.isEmpty {
            VStack {
                Image(systemName: "bell.slash")
                Text("No events")
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.messages.prefix(4)) { m in
                    HStack {
                        Text(m.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(m.receivedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
        }
    }
}
