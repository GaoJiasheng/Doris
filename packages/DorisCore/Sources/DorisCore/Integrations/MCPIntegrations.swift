#if os(macOS)

import Foundation
import DorisIPC

/// Agents (MCP clients) that Doris can register itself with as a stdio MCP
/// server — `~/.doris/bin/doris mcp` — so the agent can read and change the
/// user's tasks. The same entries `claude mcp add -s user` and
/// `codex mcp add` write.
public let dorisMCPIntegrationProviders: [any IntegrationProvider] = [
    ClaudeCodeMCPIntegration(),
    CodexMCPIntegration(),
]

/// An MCP registration, plus the optional usage hint in the agent's global
/// instructions file.
protocol AgentMCPIntegration: CLIPathBakingIntegration {
    /// CLAUDE.md / AGENTS.md — where the agent reads the user's standing
    /// instructions.
    var hintURL: URL { get }
}

extension AgentMCPIntegration {
    /// Put the hint in or take it out, per the setting. Only while registered.
    func syncHint() {
        if AgentSettings.writeHints && bakedCLIPath() != nil {
            try? AgentHintFile.install(at: hintURL)
        } else {
            try? AgentHintFile.remove(at: hintURL)
        }
    }

    /// The command to register: the stable link (repointed at every launch),
    /// or whichever CLI can be found.
    func mcpCommand() throws -> String {
        if DorisCLILink.refresh() { return DorisCLILink.path }
        guard let path = DorisCLILocator.resolve() else { throw IntegrationError.cliNotInstalled }
        return path
    }

    func mcpStatus() -> IntegrationStatus {
        guard let command = bakedCLIPath() else { return .notRegistered }
        guard FileManager.default.isExecutableFile(atPath: command) else { return .brokenHook(command) }
        return .registered
    }
}

// MARK: - Claude Code

/// Claude Code reads user-scope MCP servers from `~/.claude.json`
/// (`mcpServers.<name>`), the file `claude mcp add -s user` edits.
public struct ClaudeCodeMCPIntegration: IntegrationProvider, AgentMCPIntegration {
    public let id = "claude-code-mcp"
    public let displayName = "Claude Code"
    public let summary = "Let Claude Code read and update your tasks (MCP server in ~/.claude.json)."
    public let iconSymbol = "sparkles"
    public let sourceKind: SourceKind = .claudeCode
    public let clickURL: URL? = nil
    public let supportTier: IntegrationSupportTier = .full
    public let tutorialURL: URL? = nil

    public init() {}

    var configURL: URL { integrationsRealHome().appendingPathComponent(".claude.json") }
    var hintURL: URL { integrationsRealHome().appendingPathComponent(".claude/CLAUDE.md") }

    public func currentStatus() async -> IntegrationStatus { mcpStatus() }

    func bakedCLIPath() -> String? {
        guard let root = try? readConfig(),
              let entry = (root["mcpServers"] as? [String: Any])?["doris"] as? [String: Any] else { return nil }
        return entry["command"] as? String
    }

    public func register() async throws {
        let command = try mcpCommand()
        var root = try readConfig()
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["doris"] = ["type": "stdio", "command": command, "args": ["mcp"], "env": [String: String]()]
        root["mcpServers"] = servers
        try writeConfig(root)
        syncHint()
    }

    public func unregister() async throws {
        defer { try? AgentHintFile.remove(at: hintURL) }
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        var root = try readConfig()
        guard var servers = root["mcpServers"] as? [String: Any], servers["doris"] != nil else { return }
        servers.removeValue(forKey: "doris")
        root["mcpServers"] = servers
        try writeConfig(root)
    }

    private func readConfig() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: configURL)
            guard !data.isEmpty else { return [:] }
            return try JSONSerialization.jsonObject(with: data, options: [.mutableContainers]) as? [String: Any] ?? [:]
        } catch {
            throw IntegrationError.readFailed(path: configURL.path, underlying: error)
        }
    }

    /// The sandbox grants this one file (see the app's entitlements), and
    /// that covers an atomic replace of it too.
    private func writeConfig(_ root: [String: Any]) throws {
        do {
            var data = try JSONSerialization.data(withJSONObject: root,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            data.append(0x0a)
            let perms = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.posixPermissions]
            try data.write(to: configURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: perms ?? 0o600], ofItemAtPath: configURL.path)
        } catch {
            throw IntegrationError.writeFailed(path: configURL.path, underlying: error)
        }
    }
}

// MARK: - Codex

/// Codex reads MCP servers from `[mcp_servers.<name>]` tables in
/// `~/.codex/config.toml` — what `codex mcp add` writes.
public struct CodexMCPIntegration: IntegrationProvider, AgentMCPIntegration {
    public let id = "codex-mcp"
    public let displayName = "Codex"
    public let summary = "Let Codex read and update your tasks (MCP server in ~/.codex/config.toml)."
    public let iconSymbol = "terminal"
    public let sourceKind: SourceKind = .codex
    public let clickURL: URL? = nil
    public let supportTier: IntegrationSupportTier = .full
    public let tutorialURL: URL? = nil

    static let tableHeader = "[mcp_servers.doris]"

    public init() {}

    var configURL: URL { CodexIntegration.codexHomeURL.appendingPathComponent("config.toml") }
    var hintURL: URL { CodexIntegration.codexHomeURL.appendingPathComponent("AGENTS.md") }

    public func currentStatus() async -> IntegrationStatus { mcpStatus() }

    func bakedCLIPath() -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        return Self.command(in: text)
    }

    public func register() async throws {
        let command = try mcpCommand()
        let fm = FileManager.default
        try? fm.createDirectory(at: CodexIntegration.codexHomeURL, withIntermediateDirectories: true)
        let current = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let perms = (try? fm.attributesOfItem(atPath: configURL.path))?[.posixPermissions]
        let block = [Self.tableHeader,
                     "command = \(CodexIntegration.tomlString(command))",
                     "args = [\"mcp\"]"]
        do {
            try Self.upserting(block, in: current).write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: configURL.path, underlying: error)
        }
        try? fm.setAttributes([.posixPermissions: perms ?? 0o600], ofItemAtPath: configURL.path)
        syncHint()
    }

    public func unregister() async throws {
        defer { try? AgentHintFile.remove(at: hintURL) }
        guard let current = try? String(contentsOf: configURL, encoding: .utf8),
              Self.command(in: current) != nil else { return }
        let perms = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.posixPermissions]
        do {
            try Self.removing(from: current).write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: configURL.path, underlying: error)
        }
        if let perms { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: configURL.path) }
    }

    // MARK: TOML table surgery

    /// Line ranges of `[mcp_servers.doris]` and its sub-tables
    /// (`[mcp_servers.doris.env]`), each running to the next table header.
    static func ourTables(_ lines: [String]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t == tableHeader || t.hasPrefix("[mcp_servers.doris.") {
                var end = i + 1
                while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
                ranges.append(i..<end)
                i = end
            } else {
                i += 1
            }
        }
        return ranges
    }

    static func command(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let table = ourTables(lines).first(where: {
            lines[$0.lowerBound].trimmingCharacters(in: .whitespaces) == tableHeader
        }) else { return nil }
        for line in lines[table] {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("command") else { continue }
            let value = t.drop(while: { $0 != "=" }).dropFirst().trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { continue }
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return nil
    }

    /// Replace our table where it is, or add it at the end.
    static func upserting(_ block: [String], in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let tables = ourTables(lines)
        if let first = tables.first {
            for r in tables.reversed() { lines.removeSubrange(r) }
            // Keep a blank line between our table and whatever follows.
            lines.insert(contentsOf: block + [""], at: first.lowerBound)
            return lines.joined(separator: "\n")
        }
        var out = text
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty && !out.hasSuffix("\n\n") { out += "\n" }
        return out + block.joined(separator: "\n") + "\n"
    }

    static func removing(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        for r in ourTables(lines).reversed() { lines.removeSubrange(r) }
        // Don't leave a run of blank lines where the table was.
        var out: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty, out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { continue }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - Usage hint

/// A short, clearly marked section in the agent's global instructions file
/// telling it *when* to reach for Doris. MCP describes how to use a server
/// but never makes an agent think of it; this does. Opt-in, because it's
/// the user's file.
enum AgentHintFile {
    static let begin = "<!-- doris:begin -->"
    static let end = "<!-- doris:end -->"
    static let body = """
    ## Doris (to-dos)

    The user keeps their to-dos in Doris — the menu-bar app on this Mac, synced to their iPhone. When they ask you to remember, note down or track something to do ("记一下", "加个待办", "remind me to…"), or ask what's left today, use the `doris` MCP tools rather than a TODO file or your own memory.
    """

    static func install(at url: URL) throws {
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var text = stripped(current)
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += "\(begin)\n\(body)\n\(end)\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func remove(at url: URL) throws {
        guard let current = try? String(contentsOf: url, encoding: .utf8), current.contains(begin) else { return }
        let text = stripped(current)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try FileManager.default.removeItem(at: url)   // the file only ever held our section
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// The text without our section (and the blank line before it).
    static func stripped(_ text: String) -> String {
        guard let b = text.range(of: begin), let e = text.range(of: end, range: b.upperBound..<text.endIndex) else { return text }
        var head = String(text[..<b.lowerBound])
        var tail = String(text[e.upperBound...])
        if tail.hasPrefix("\n") { tail.removeFirst() }
        while head.hasSuffix("\n\n") { head.removeLast() }
        return head + tail
    }
}

#endif // os(macOS)
