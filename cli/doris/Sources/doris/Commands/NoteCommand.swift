import ArgumentParser
import Foundation
import DorisIPC

struct NoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Create or query notes.",
        subcommands: [Add.self, List.self, Show.self, Edit.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Create a new note.")

        @Option(name: .shortAndLong) var title: String
        @Option(name: .shortAndLong) var body: String?
        @Flag(name: .customLong("body-stdin")) var bodyStdin: Bool = false
        @Option(name: .shortAndLong) var folder: String?
        @Option(name: .customLong("tag")) var tags: [String] = []
        @Flag(name: .shortAndLong) var quiet: Bool = false

        func run() async throws {
            var resolvedBody = body ?? ""
            if bodyStdin {
                let data = FileHandle.standardInput.availableData
                resolvedBody = String(decoding: data, as: UTF8.self)
            }
            let payload = IPCNoteAddPayload(title: title, body: resolvedBody, folderName: folder, tags: tags)
            let request = IPCRequest(kind: .noteAdd, payload: .noteAdd(payload))

            try? IPCDirectory.ensureIPCDirectories()
            do {
                try IPCWriter.enqueue(request)
                IPCWriter.kick()
            } catch {
                dieIO("doris: failed to enqueue note: \(error)")
            }
            if !AppLauncher.isRunning() { _ = AppLauncher.launchIfNeeded() }
            info("doris: queued note \(request.id.uuidString)", quiet: quiet)
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "ls", abstract: "List notes.")

        func run() async throws {
            print("doris: note listing requires the running app to respond via IPC. (v0.1: not yet implemented in CLI; use the app UI.)")
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show a note by id.")
        @Argument var id: String
        func run() async throws {
            print("doris: show \(id) — not yet implemented in CLI; use the app UI.")
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "edit", abstract: "Append to an existing note.")
        @Argument var id: String
        @Option(name: .customLong("append")) var append: String?
        @Flag(name: .customLong("body-stdin")) var bodyStdin: Bool = false
        func run() async throws {
            print("doris: edit \(id) — not yet implemented in CLI; use the app UI.")
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "Delete a note.")
        @Argument var id: String
        func run() async throws {
            print("doris: rm \(id) — not yet implemented in CLI; use the app UI.")
        }
    }
}
