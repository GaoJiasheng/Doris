import XCTest
import DorisIPC
@testable import doris

final class MCPServerTests: XCTestCase {
    /// Records what reaches "the app" and answers with a canned result.
    final class FakeBackend: AgentBackend, @unchecked Sendable {
        var calls: [(tool: String, arguments: [String: Any], client: String)] = []
        func call(tool: String, arguments: String, client: String) async -> IPCAgentResult {
            let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
            calls.append((tool, args, client))
            return IPCAgentResult(text: #"{"ok":true}"#)
        }
    }

    private func send(_ server: MCPServer, _ json: String) async throws -> [String: Any] {
        let reply = await server.handle(line: json)
        let line = try XCTUnwrap(reply)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func testInitializeNegotiatesAndCarriesTheManual() async throws {
        let server = MCPServer(backend: FakeBackend(), version: "1.10.0")
        let r = try await send(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"claude-code","version":"2"}}}"#)
        let result = try XCTUnwrap(r["result"] as? [String: Any])
        XCTAssertEqual(r["id"] as? Int, 1)
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertTrue((result["instructions"] as? String)?.contains("list_tasks") == true)
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["version"] as? String, "1.10.0")
        XCTAssertEqual(server.clientName, "claude-code")

        let unknown = try await send(server, #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.protocolVersions[0])
        XCTAssertEqual(unknown["id"] as? String, "a", "string ids come back as strings")
    }

    func testToolsListMatchesWhatTheAppRuns() async throws {
        let server = MCPServer(backend: FakeBackend(), version: "t")
        let r = try await send(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((r["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), Set(AgentTool.allCases.map(\.rawValue)))
        for t in tools {
            XCTAssertNotNil(t["inputSchema"] as? [String: Any])
            XCTAssertFalse((t["description"] as? String ?? "").isEmpty)
        }
        // The manual stays small: it rides along in every conversation.
        let size = try JSONSerialization.data(withJSONObject: tools).count + MCPCatalog.instructions.utf8.count
        XCTAssertLessThan(size, 9_000, "tool descriptions + instructions grew to \(size) bytes")
    }

    func testToolCallsGoToTheBackendWithTheClientName() async throws {
        let backend = FakeBackend()
        let server = MCPServer(backend: backend, version: "t")
        _ = try await send(server, #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"clientInfo":{"name":"codex-mcp-client"}}}"#)
        let r = try await send(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_task","arguments":{"title":"Gym","items":["a"]}}}"#)
        let result = try XCTUnwrap(r["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertEqual(((result["content"] as? [[String: Any]])?.first)?["text"] as? String, #"{"ok":true}"#)
        XCTAssertEqual(backend.calls.first?.tool, "create_task")
        XCTAssertEqual(backend.calls.first?.arguments["title"] as? String, "Gym")
        XCTAssertEqual(backend.calls.first?.client, "codex-mcp-client")
    }

    func testUnknownToolIsAnsweredWithoutWakingTheApp() async throws {
        let backend = FakeBackend()
        let r = try await send(MCPServer(backend: backend, version: "t"),
                               #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"delete_task","arguments":{}}}"#)
        XCTAssertEqual((r["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testPrompts() async throws {
        let server = MCPServer(backend: FakeBackend(), version: "t")
        let list = try await send(server, #"{"jsonrpc":"2.0","id":5,"method":"prompts/list"}"#)
        XCTAssertEqual(((list["result"] as? [String: Any])?["prompts"] as? [[String: Any]])?.compactMap { $0["name"] as? String },
                       ["today", "plan", "wrapup"])
        let plan = try await send(server, #"{"jsonrpc":"2.0","id":6,"method":"prompts/get","params":{"name":"plan","arguments":{"goal":"move house"}}}"#)
        let messages = try XCTUnwrap((plan["result"] as? [String: Any])?["messages"] as? [[String: Any]])
        XCTAssertTrue(((messages.first?["content"] as? [String: Any])?["text"] as? String)?.contains("\"move house\"") == true)
        let missing = try await send(server, #"{"jsonrpc":"2.0","id":7,"method":"prompts/get","params":{"name":"nope"}}"#)
        XCTAssertEqual((missing["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testNotificationsAndJunk() async throws {
        let server = MCPServer(backend: FakeBackend(), version: "t")
        let none = await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(none)
        let parse = try await send(server, "{not json")
        XCTAssertEqual((parse["error"] as? [String: Any])?["code"] as? Int, -32700)
        let unknown = try await send(server, #"{"jsonrpc":"2.0","id":8,"method":"sampling/createMessage"}"#)
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let ping = try await send(server, #"{"jsonrpc":"2.0","id":9,"method":"ping"}"#)
        XCTAssertNotNil(ping["result"])
    }

    func testBatches() async throws {
        let server = MCPServer(backend: FakeBackend(), version: "t")
        let reply = await server.handle(line: #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"}]"#)
        let line = try XCTUnwrap(reply)
        let replies = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [[String: Any]])
        XCTAssertEqual(replies.count, 1)
    }
}
