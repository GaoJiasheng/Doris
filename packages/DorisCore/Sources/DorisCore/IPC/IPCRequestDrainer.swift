import Foundation
import DorisIPC

/// Drains pending IPC request files from the App Group "IPC/inbox" queue
/// directory, hands each one to the `NotificationRouter`, and moves the
/// file to "IPC/processed" with an outcome suffix. Despite the queue
/// dir's filesystem name still being `inbox` (the IPC mailbox metaphor),
/// what flows through is every IPC request kind (notify, noteAdd,
/// eventsList, sync, ping…), so the type is named after what it does
/// rather than the dir it watches.
@MainActor
public final class IPCRequestDrainer {
    private let router: NotificationRouter
    private let secret: Data?

    public init(router: NotificationRouter, secret: Data?) {
        self.router = router
        self.secret = secret
    }

    public func drain() async {
        let inbox: URL
        do {
            inbox = try IPCDirectory.inboxDir()
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        } catch {
            DorisLog.ipc.error("inbox unavailable: \(String(describing: error), privacy: .public)")
            return
        }
        let processed = (try? IPCDirectory.processedDir()) ?? inbox.deletingLastPathComponent().appendingPathComponent("processed")
        try? FileManager.default.createDirectory(at: processed, withIntermediateDirectories: true)

        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        let sorted = files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in sorted {
            await processOne(url, processedDir: processed)
        }
        IPCResponseStore.pruneStale()
    }

    private func processOne(_ url: URL, processedDir: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let request = try IPCEncoding.decoder.decode(IPCRequest.self, from: data)
            if let secret {
                do {
                    try DorisHMAC.verify(request, with: secret)
                } catch {
                    DorisLog.ipc.error("HMAC verification failed for \(url.lastPathComponent, privacy: .public)")
                    if case .agentCall = request.payload {
                        // Answer, so the agent hears why instead of timing out.
                        NotificationRouter.respond(to: request.id, with: IPCAgentResult(
                            text: "Doris refused this request: its signature didn't check out. Restart Doris and try again.",
                            isError: true))
                    }
                    try? moveToProcessed(url, into: processedDir, suffix: ".rejected")
                    return
                }
            }
            await router.handle(request)
            if case .agentCall = request.payload {
                // Agent calls carry the user's task text, and the response
                // is their record — don't keep a copy lying around.
                try? FileManager.default.removeItem(at: url)
            } else {
                try? moveToProcessed(url, into: processedDir, suffix: ".ok")
            }
        } catch {
            DorisLog.ipc.error("failed to process \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            try? moveToProcessed(url, into: processedDir, suffix: ".error")
        }
    }

    private func moveToProcessed(_ url: URL, into dir: URL, suffix: String) throws {
        let dest = dir.appendingPathComponent(url.lastPathComponent + suffix)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: url, to: dest)
    }
}
