import ArgumentParser
import Foundation

@main
struct Doris: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doris",
        abstract: "Push notifications, notes, and events commands to your doris helper.",
        version: "1.2.2",
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

    /// Invoked through `~/.codex/doris-notify-dispatch.sh` (see
    /// `CodexNotifyDispatch`), answer as `doris notify` for Codex instead
    /// of parsing Codex's payload as a subcommand.
    static func main() async {
        if CodexNotifyDispatch.matches(CommandLine.arguments.first) {
            await NotifyCommand.main(CodexNotifyDispatch.notifyArguments())
            return
        }
        await main(nil)
    }
}
