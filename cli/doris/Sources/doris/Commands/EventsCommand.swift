import ArgumentParser
import Foundation
import DorisIPC

struct EventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Inspect or mutate the event list.",
        subcommands: [List.self, Tail.self, Dismiss.self, Done.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "ls", abstract: "List recent events.")
        @Option var source: String?
        @Option(name: .customLong("since-secs")) var sinceSecs: Double?
        @Flag(name: .customLong("unread")) var unread: Bool = false
        @Option var limit: Int?

        func run() async throws {
            let payload = IPCEventsListPayload(
                source: source.flatMap(SourceKind.init(rawValue:)),
                sinceSeconds: sinceSecs,
                unreadOnly: unread,
                limit: limit
            )
            let request = IPCRequest(kind: .eventsList, payload: .eventsList(payload))
            try? IPCDirectory.ensureIPCDirectories()
            do {
                try IPCWriter.enqueue(request)
                IPCWriter.kick()
            } catch {
                dieIO("doris: failed to enqueue request: \(error)")
            }
            print("doris: requested events list (response streams via app outbox; reader UI not yet implemented in CLI v0.1)")
        }
    }

    struct Tail: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tail", abstract: "Stream new events as they arrive.")
        func run() async throws {
            print("doris: events tail — long-running stream not yet implemented in CLI v0.1; use the app events view.")
        }
    }

    struct Dismiss: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "dismiss", abstract: "Dismiss an event by id.")
        @Argument var id: String
        func run() async throws {
            guard let uuid = UUID(uuidString: id) else { dieUsage("doris: invalid event id") }
            let request = IPCRequest(kind: .eventsDismiss, payload: .eventsDismiss(messageID: uuid))
            try? IPCDirectory.ensureIPCDirectories()
            try IPCWriter.enqueue(request)
            IPCWriter.kick()
            print("doris: dismiss queued")
        }
    }

    struct Done: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "done", abstract: "Mark an event as actioned.")
        @Argument var id: String
        func run() async throws {
            guard let uuid = UUID(uuidString: id) else { dieUsage("doris: invalid event id") }
            let request = IPCRequest(kind: .eventsDone, payload: .eventsDone(messageID: uuid))
            try? IPCDirectory.ensureIPCDirectories()
            try IPCWriter.enqueue(request)
            IPCWriter.kick()
            print("doris: done queued")
        }
    }
}
