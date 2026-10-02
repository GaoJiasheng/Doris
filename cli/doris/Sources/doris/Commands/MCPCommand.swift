import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve Doris to AI agents over MCP (stdio).",
        discussion: """
        Add Doris to an agent as a stdio MCP server whose command is this \
        binary with the argument `mcp` — Doris → Settings → Agents does it \
        for Claude Code and Codex. Agents can then list, create, update, \
        tick off and archive the user's tasks. Nothing can be deleted.

        `doris mcp --config` prints the JSON that most other clients \
        (Claude Desktop, Cursor, LM Studio) take.
        """
    )

    @Flag(name: .customLong("config"), help: "Print an MCP client configuration for this binary and exit.")
    var printConfig = false

    func run() async throws {
        if printConfig {
            print(Self.clientConfig())
            return
        }
        if isatty(STDIN_FILENO) != 0 {
            FileHandle.standardError.write(Data("""
            doris mcp talks to AI agents over stdin/stdout — add it to your agent \
            rather than running it here. `doris mcp --config` prints the setup.\n
            """.utf8))
        }
        await MCPServer(backend: AgentBridge(), version: DorisVersion.current).serve()
    }

    /// `{"mcpServers": {"doris": {...}}}` pointing at the stable link when
    /// there is one, so the entry survives the app moving.
    static func clientConfig() -> String {
        let link = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".doris/bin/doris").path
        let command = FileManager.default.isExecutableFile(atPath: link) ? link : DorisVersion.executablePath
        let config: [String: Any] = ["mcpServers": ["doris": ["command": command, "args": ["mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// The version of the Doris app this CLI ships inside, read from the app's
/// Info.plist (the CLI lives at Doris.app/Contents/Resources/doris).
enum DorisVersion {
    static var executablePath: String {
        URL(fileURLWithPath: CommandLine.arguments.first ?? "doris").resolvingSymlinksInPath().path
    }

    static let current: String = {
        let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? executablePath).resolvingSymlinksInPath()
        let plist = exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: plist),
           let v = info["CFBundleShortVersionString"] as? String {
            return v
        }
        return "dev"
    }()
}
