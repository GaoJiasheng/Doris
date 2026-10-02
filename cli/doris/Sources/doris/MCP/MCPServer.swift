import Foundation
import DorisIPC

/// Carries a tool call to whatever executes it — the app, through IPC
/// (`AgentBridge`), or a stand-in in tests.
protocol AgentBackend: Sendable {
    func call(tool: String, arguments: String, client: String) async -> IPCAgentResult
}

/// A Model Context Protocol server over stdio: newline-delimited JSON-RPC
/// 2.0 on stdin/stdout, as Claude Code, Codex, Claude Desktop, Cursor and
/// LM Studio all speak it.
///
/// This side only describes Doris (see `MCPCatalog`) and relays tool calls;
/// the app owns the store and does the work. Nothing but protocol messages
/// may go to stdout — diagnostics go to stderr.
final class MCPServer: @unchecked Sendable {
    /// Newest first. A client asking for one of these gets it back;
    /// anything else gets the newest, per the spec's negotiation rule.
    static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let backend: AgentBackend
    private let version: String
    private(set) var clientName = ""

    init(backend: AgentBackend, version: String) {
        self.backend = backend
        self.version = version
    }

    func serve() async {
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                if let reply = await handle(line: line) {
                    FileHandle.standardOutput.write(Data((reply + "\n").utf8))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("doris mcp: stdin closed: \(error)\n".utf8))
        }
    }

    /// One incoming line → the line to send back, if any (notifications
    /// get no reply).
    func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
            return encode(errorReply(id: NSNull(), code: -32700, message: "Parse error"))
        }
        if let batch = parsed as? [Any] {
            var replies: [Any] = []
            for item in batch {
                guard let message = item as? [String: Any] else {
                    replies.append(errorReply(id: NSNull(), code: -32600, message: "Invalid request"))
                    continue
                }
                if let r = await handle(message: message) { replies.append(r) }
            }
            return replies.isEmpty ? nil : encode(replies)
        }
        guard let message = parsed as? [String: Any] else {
            return encode(errorReply(id: NSNull(), code: -32600, message: "Invalid request"))
        }
        return await handle(message: message).map(encode)
    }

    func handle(message: [String: Any]) async -> [String: Any]? {
        // Responses to requests we never send, and notifications: no reply.
        guard let method = message["method"] as? String else { return nil }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String {
                clientName = name
            }
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]
            return result(id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false], "prompts": ["listChanged": false]],
                "serverInfo": ["name": "doris", "title": "Doris", "version": self.version],
                "instructions": MCPCatalog.instructions,
            ])
        case "ping", "logging/setLevel":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": MCPCatalog.tools()])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return errorReply(id: id, code: -32602, message: "tools/call needs a tool name")
            }
            guard AgentTool(rawValue: name) != nil else {
                // Answered here: no point waking the app for a typo.
                let names = AgentTool.allCases.map(\.rawValue).joined(separator: ", ")
                return result(id, toolResult(IPCAgentResult(text: "Unknown tool \"\(name)\". Doris has: \(names).", isError: true)))
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: args)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            let outcome = await backend.call(tool: name, arguments: json, client: clientName)
            return result(id, toolResult(outcome))
        case "prompts/list":
            return result(id, ["prompts": MCPCatalog.prompts.map { p -> [String: Any] in
                ["name": p.name, "title": p.title, "description": p.description, "arguments": p.arguments]
            }])
        case "prompts/get":
            guard let name = params["name"] as? String,
                  let prompt = MCPCatalog.prompts.first(where: { $0.name == name }) else {
                return errorReply(id: id, code: -32602, message: "Unknown prompt")
            }
            let args = (params["arguments"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            return result(id, [
                "description": prompt.description,
                "messages": [["role": "user", "content": ["type": "text", "text": prompt.text(args)]]],
            ])
        case "resources/list":
            return result(id, ["resources": [Any]()])
        case "resources/templates/list":
            return result(id, ["resourceTemplates": [Any]()])
        default:
            return errorReply(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func toolResult(_ r: IPCAgentResult) -> [String: Any] {
        ["content": [["type": "text", "text": r.text]], "isError": r.isError]
    }

    private func result(_ id: Any, _ body: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": body]
    }

    private func errorReply(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
