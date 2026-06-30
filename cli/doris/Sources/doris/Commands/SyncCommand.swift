import ArgumentParser
import Foundation
import DorisIPC

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Force the running app to poke CloudKit now."
    )

    func run() async throws {
        let request = IPCRequest(kind: .sync, payload: .sync)
        try? IPCDirectory.ensureIPCDirectories()
        try IPCWriter.enqueue(request)
        IPCWriter.kick()
        if !AppLauncher.isRunning() { _ = AppLauncher.launchIfNeeded() }
        print("doris: sync queued")
    }
}
