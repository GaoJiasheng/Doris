#if os(macOS)

import Foundation

/// Installs (or restores) Doris as Claude Code's `statusLine` command in
/// `~/.claude/settings.json`. That's the only supported way to receive the
/// real subscription `rate_limits` — Claude Code pipes them to the
/// status-line command, which `doris claude-statusline` captures. Opt-in,
/// and non-destructive: any pre-existing statusLine is saved and restored.
@MainActor
public enum ClaudeStatusLineInstaller {
    static let marker = "claude-statusline"

    private static var settingsURL: URL {
        integrationsRealHome()
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public static func install() throws {
        guard let cli = DorisCLILocator.resolve() else { throw IntegrationError.cliNotInstalled }
        var root = try readSettings()

        if let existing = root["statusLine"] as? [String: Any],
           (existing["command"] as? String)?.contains(marker) == true {
            // Already ours — nothing to back up.
        } else if let existing = root["statusLine"] {
            // Preserve the user's current statusLine so we can restore it.
            if let data = try? JSONSerialization.data(withJSONObject: existing),
               let s = String(data: data, encoding: .utf8) {
                TokenMonitorSettings.shared.savedStatusLine = s
            }
        } else {
            TokenMonitorSettings.shared.savedStatusLine = nil
        }

        let quoted = cli.contains(" ") ? "'\(cli)'" : cli
        root["statusLine"] = [
            "type": "command",
            "command": "\(quoted) claude-statusline",
            "padding": 0
        ]
        try writeSettings(root)
    }

    public static func uninstall() throws {
        var root = try readSettings()
        guard let existing = root["statusLine"] as? [String: Any],
              (existing["command"] as? String)?.contains(marker) == true else {
            return  // not ours — leave the user's own statusLine alone
        }
        if let saved = TokenMonitorSettings.shared.savedStatusLine,
           let data = saved.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            root["statusLine"] = obj
        } else {
            root.removeValue(forKey: "statusLine")
        }
        TokenMonitorSettings.shared.savedStatusLine = nil
        try writeSettings(root)
    }

    // MARK: settings.json IO (mirrors ClaudeCodeIntegration)

    private static func readSettings() throws -> [String: Any] {
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func writeSettings(_ root: [String: Any]) throws {
        let url = settingsURL
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        do {
            var bytes = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            if bytes.last != 0x0a { bytes.append(0x0a) }
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw IntegrationError.writeFailed(path: url.path, underlying: error)
        }
    }
}

#endif
