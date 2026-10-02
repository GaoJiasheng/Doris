import Foundation
import DorisIPC

/// Relays a tool call to the Doris app and waits for its answer.
///
/// The request goes into the IPC inbox like every other CLI request (signed,
/// then a Darwin kick wakes the app); the app writes its answer to
/// `IPC/responses/<request id>.json`, which this polls for. Opens Doris
/// first if it isn't running — it owns the store, and an agent asking about
/// tasks shouldn't fail just because the menu-bar app was quit.
struct AgentBridge: AgentBackend {
    /// How long to wait for a running app. A launch gets longer.
    var timeout: TimeInterval = 15
    var launchTimeout: TimeInterval = 30

    func call(tool: String, arguments: String, client: String) async -> IPCAgentResult {
        let request = IPCRequest(kind: .agentCall,
                                 payload: .agentCall(IPCAgentCallPayload(client: client, tool: tool, arguments: arguments)))
        let file: URL
        do {
            try IPCDirectory.ensureIPCDirectories()
            file = try IPCWriter.enqueue(request)
        } catch {
            return IPCAgentResult(text: "Couldn't reach Doris: \(error)", isError: true)
        }
        IPCWriter.kick()

        var wait = timeout
        if !AppLauncher.isRunning() {
            guard AppLauncher.launchIfNeeded() else {
                try? FileManager.default.removeItem(at: file)
                return IPCAgentResult(text: "Doris isn't running and couldn't be opened. Ask the user to open the Doris app.", isError: true)
            }
            wait = launchTimeout   // it drains the inbox once it's up
        }

        if let answer = await awaitResponse(request.id, for: wait) { return answer }

        // Not answered in time. If the request is still waiting in the inbox,
        // withdraw it — a change that lands after the agent was told it
        // failed would surprise everyone.
        if (try? FileManager.default.removeItem(at: file)) != nil {
            return IPCAgentResult(text: "Doris didn't answer in time, and nothing was changed. Ask the user to check that the Doris app is open, then try again.", isError: true)
        }
        // Already picked up: give it a little longer.
        if let answer = await awaitResponse(request.id, for: 10) { return answer }
        return IPCAgentResult(text: "Doris is taking unusually long to answer. The change may or may not have gone through — check with list_tasks before trying again.", isError: true)
    }

    private func awaitResponse(_ id: UUID, for seconds: TimeInterval) async -> IPCAgentResult? {
        let deadline = Date().addingTimeInterval(seconds)
        var lastKick = Date()
        while Date() < deadline {
            if let response = IPCResponseStore.take(id) {
                if let data = response.data, let result = try? IPCEncoding.decoder.decode(IPCAgentResult.self, from: data) {
                    return result
                }
                return IPCAgentResult(text: response.error ?? "Doris answered, but the answer was empty.", isError: !response.ok)
            }
            // A kick can be missed (the app was still launching); repeat it.
            if Date().timeIntervalSince(lastKick) > 2 {
                IPCWriter.kick()
                lastKick = Date()
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return nil
    }
}
