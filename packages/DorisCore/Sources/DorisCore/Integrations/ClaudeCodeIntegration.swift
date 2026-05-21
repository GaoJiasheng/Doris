import Foundation
import DorisIPC

/// Claude Code integration — wires a `Stop` hook into the user's
/// `~/.claude/settings.json` so every Claude Code session-end fires
/// `doris notify` through the bundled CLI.
///
/// Hook JSON shape (matches Claude Code's documented schema):
/// ```json
/// {
///   "hooks": {
///     "Stop": [
///       {
///         "hooks": [
///           {
///             "type": "command",
///             "command": "/abs/path/to/doris notify ... # doris-integration"
///           }
///         ]
///       }
///     ]
///   }
/// }
/// ```
///
/// Detection / cleanup uses the trailing `# doris-integration` shell
/// comment as a marker — it's ignored by the shell at execution time
/// but makes the hook easy to find without parsing the command line.
/// Any user-authored hooks in the same `Stop` array are preserved.
public struct ClaudeCodeIntegration: IntegrationProvider {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let summary = "Hook Stop event → Doris banner with click-to-open."
    public let iconSymbol = "sparkles"
    public let sourceKind: SourceKind = .claudeCode
    public let clickURL: URL? = URL(string: "claude://")
    public let supportTier: IntegrationSupportTier = .full
    public let tutorialURL: URL? = nil

    /// Marker baked into the hook command so we can find it later
    /// without remembering the whole command string. Treated as a
    /// shell comment by the executor — no runtime side effect.
    static let marker = "# doris-integration"

    private var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public init() {}

    public func currentStatus() async -> IntegrationStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else {
            return .notRegistered
        }
        guard let data = try? Data(contentsOf: settingsURL) else {
            return .error("Couldn't read ~/.claude/settings.json")
        }
        // Lenient marker search — we don't need to fully parse the
        // tree. If the file is malformed JSON we still find our
        // marker (or don't); if it's missing we return not-registered.
        // The full structural read happens only at register/unregister
        // time where we need to mutate.
        if let text = String(data: data, encoding: .utf8),
           text.contains(Self.marker) {
            // Marker is there — verify the CLI it points to still resolves.
            if DorisCLILocator.resolve() == nil {
                return .missingCLI
            }
            return .registered
        }
        return .notRegistered
    }

    public func register() async throws {
        guard let cliPath = DorisCLILocator.resolve() else {
            throw IntegrationError.cliNotInstalled
        }
        let command = Self.hookCommand(cliPath: cliPath)
        var root = try readSettings()
        appendStopHook(into: &root, command: command)
        try writeSettings(root)
    }

    public func unregister() async throws {
        var root: [String: Any]
        do {
            root = try readSettings()
        } catch IntegrationError.readFailed {
            // No file → nothing to unregister, idempotent success.
            return
        }
        removeDorisHooks(from: &root)
        try writeSettings(root)
    }

    // MARK: - Hook command shape

    static func hookCommand(cliPath: String) -> String {
        // Single-quoted strings keep the body safe from shell expansion
        // in case Claude Code spawns the hook via /bin/sh -c. The
        // trailing marker is a shell comment ignored at execution.
        // CLI option name is `--click-url` (not `--click`); earlier
        // versions of this provider wrote `--click` and Claude Code's
        // Stop hook silently exited 64 ("Unknown option '--click'")
        // every time. Re-registering refreshes the command in place.
        //
        // Level = reminder (4s + orange progress bar). `info` (1.5s)
        // disappears before the user can react to "task done"; reminder
        // is the sweet spot — long enough to read + click-through, not
        // so persistent that you have to dismiss like critical.
        //
        // Title is localized at registration time by reading the same
        // UserDefaults key LanguageSettings (in DorisUI) writes to.
        // Frozen into the hook command — if the user changes language
        // later, re-registering refreshes the command in place.
        let quotedPath = cliPath.contains(" ") ? "'\(cliPath)'" : cliPath
        let title = localizedTitle()
        return "\(quotedPath) notify --title '\(title)' --source claudeCode --level reminder --click-url 'claude://' \(marker)"
    }

    /// Pick the title for the user's current language. Reads the same
    /// `doris.language.mode` key that DorisUI's `LanguageSettings`
    /// writes to, so we don't have to depend on DorisUI from this
    /// (DorisCore-internal) integration module.
    private static func localizedTitle() -> String {
        let mode = UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh"
        return mode == "en" ? "Claude task complete" : "Claude 任务完成"
    }

    // MARK: - JSON read / mutate / write

    /// Read the existing settings.json or return an empty dictionary
    /// if the file is absent. Throws only on permission / parse error.
    private func readSettings() throws -> [String: Any] {
        let fm = FileManager.default
        let url = settingsURL
        guard fm.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IntegrationError.readFailed(path: url.path, underlying: error)
        }
        guard !data.isEmpty else { return [:] }
        do {
            let any = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
            return (any as? [String: Any]) ?? [:]
        } catch {
            throw IntegrationError.readFailed(path: url.path, underlying: error)
        }
    }

    /// Write the settings.json back out with pretty indentation and a
    /// trailing newline so it diffs cleanly if the user version-controls
    /// their `~/.claude/`.
    private func writeSettings(_ root: [String: Any]) throws {
        let url = settingsURL
        let parent = url.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parent.path) {
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw IntegrationError.writeFailed(path: parent.path, underlying: error)
            }
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            var bytes = data
            if bytes.last != 0x0a { bytes.append(0x0a) }
            try bytes.write(to: url, options: .atomic)
        } catch let err as IntegrationError {
            throw err
        } catch {
            throw IntegrationError.writeFailed(path: url.path, underlying: error)
        }
    }

    /// Add (or replace) the Doris Stop hook in-place. The function
    /// is structured to preserve unrelated keys at every level of
    /// the JSON tree — only the Stop array gets edited.
    private func appendStopHook(into root: inout [String: Any], command: String) {
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        var stopArr = (hooks["Stop"] as? [[String: Any]]) ?? []

        // Drop any existing Doris-marked entries so register() is a
        // safe upsert and re-registering after a CLI path change
        // refreshes the absolute path baked in.
        stopArr = stopArr.compactMap { entry in
            var entry = entry
            if var inner = entry["hooks"] as? [[String: Any]] {
                inner.removeAll { ($0["command"] as? String)?.contains(Self.marker) == true }
                if inner.isEmpty { return nil }
                entry["hooks"] = inner
            }
            return entry
        }

        let dorisEntry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": command
                ]
            ]
        ]
        stopArr.append(dorisEntry)

        hooks["Stop"] = stopArr
        root["hooks"] = hooks
    }

    /// Strip every Doris-marked hook out of the tree, then garbage-
    /// collect emptied containers so we don't leave `hooks.Stop = []`
    /// noise behind.
    private func removeDorisHooks(from root: inout [String: Any]) {
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        guard var stopArr = hooks["Stop"] as? [[String: Any]] else { return }

        stopArr = stopArr.compactMap { entry in
            var entry = entry
            if var inner = entry["hooks"] as? [[String: Any]] {
                inner.removeAll { ($0["command"] as? String)?.contains(Self.marker) == true }
                if inner.isEmpty { return nil }
                entry["hooks"] = inner
            }
            return entry
        }

        if stopArr.isEmpty {
            hooks.removeValue(forKey: "Stop")
        } else {
            hooks["Stop"] = stopArr
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
    }
}
