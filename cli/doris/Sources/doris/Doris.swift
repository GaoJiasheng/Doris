import ArgumentParser
import Foundation

@main
struct Doris: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doris",
        abstract: "Push notifications, notes, and events commands to your doris helper.",
        version: "1.1.2",
        subcommands: [
            NotifyCommand.self,
            PushCommand.self,
            NoteCommand.self,
            EventsCommand.self,
            DevicesCommand.self,
            AuthCommand.self,
            SyncCommand.self,
            InstallCommand.self
        ]
    )
}
