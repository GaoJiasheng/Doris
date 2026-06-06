#if os(macOS)

import Foundation
import DorisIPC

/// Codex integration — OpenAI's agentic coding tool (desktop app +
/// CLI). Uses Codex's **native `notify` hook** in `~/.codex/config.toml`
/// — the proper analogue to Claude Code's `~/.claude/settings.json`
/// hooks. Codex invokes its configured `notify` program once per turn
/// completion, passing a JSON payload as the final argument.
///
/// ### Why not a shell wrapper?
///
/// An earlier version of this integration installed a `codex()` shell
/// function in the user's rc file. That only fires when `codex` is
/// invoked *from an interactive terminal* and the process exits — it
/// never fires for the **Codex desktop app**, where a task completes
/// while the app keeps running. Most users run the app, so the wrapper
/// was effectively dead. The `notify` hook fires for both the app and
/// the CLI, on every turn completion. We migrated to it wholesale.
///
/// ### Coexisting with the app's own notifier
///
/// On builds that ship the computer-use feature, the Codex app *owns*
/// the `notify` slot: it resets `notify[0]` to its own client
/// (`SkyComputerUseClient`) and supports a `--previous-notify` chain.
/// When Doris sets `notify = ["<dispatcher>"]`, the app absorbs the
/// dispatcher as its downstream, so the live chain becomes:
///
///     Codex  ->  SkyComputerUseClient  ->  Doris dispatcher  ->  doris CLI
///
/// Because the app's notifier ends up *upstream* of the dispatcher in
/// that case, the dispatcher must NOT call back into it (that would
/// double-fire the app's own notification). The dispatcher therefore
/// only fires the Doris banner and never forwards. On a plain CLI
/// setup where Doris's dispatcher is itself `notify[0]`, any prior
/// notifier is preserved via the backup file and restored on
/// unregister.
///
/// ### Files Doris manages
///
///   - `~/.codex/doris-notify-dispatch.sh` — the dispatcher (executable)
///   - `~/.codex/config.toml`              — `notify` points at the above
///   - `~/.codex/.doris-notify-backup`     — original `notify` line, for
///                                            clean restore on unregister
public struct CodexIntegration: IntegrationProvider {
    public let id = "codex"
    public let displayName = "Codex"
    public let summary = "Fire Doris when a Codex turn completes (notify hook)."
    public let iconSymbol = "terminal"
    public let sourceKind: SourceKind = .codex
    public let clickURL: URL? = URL(string: "codex://")
    public let supportTier: IntegrationSupportTier = .full
    public let tutorialURL: URL? = URL(string: "https://github.com/GaoJiasheng/Doris/blob/main/docs/integrations/codex.md")

    /// Begin/end markers wrapping the generated dispatcher body so the
    /// script is recognizable as Doris-managed.
    static let beginMarker = "# >>> doris-codex-notify-dispatch >>>"
    static let endMarker   = "# <<< doris-codex-notify-dispatch <<<"

    /// Dispatcher filename. Also doubles as the substring `currentStatus`
    /// greps for in config.toml — it shows up whether the dispatcher is
    /// `notify[0]` or nested inside the app's `--previous-notify`.
    static let dispatcherFilename = "doris-notify-dispatch.sh"

    /// Written into the backup file when there was no prior `notify`
    /// line — tells `unregister()` to delete the line outright rather
    /// than restore something.
    static let noOriginalMarker = "# doris: no original notify"

    public init() {}

    // MARK: - Paths

    /// `$CODEX_HOME` if set (Codex respects it), else `~/.codex`.
    static var codexHomeURL: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath,
                       isDirectory: true)
        }
        // Real home, not the sandbox container — see integrationsRealHome().
        return integrationsRealHome()
            .appendingPathComponent(".codex", isDirectory: true)
    }

    var configURL: URL { Self.codexHomeURL.appendingPathComponent("config.toml") }
    var dispatcherURL: URL { Self.codexHomeURL.appendingPathComponent(Self.dispatcherFilename) }
    var backupURL: URL { Self.codexHomeURL.appendingPathComponent(".doris-notify-backup") }

    // MARK: - Status

    public func currentStatus() async -> IntegrationStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return .notRegistered }
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .error("Couldn't read config.toml")
        }
        // Our dispatcher is referenced somewhere in the notify chain
        // (either as notify[0] or inside the app's --previous-notify).
        guard text.contains(Self.dispatcherFilename) else { return .notRegistered }
        // Config points at us, but verify the pieces are actually intact.
        guard fm.isExecutableFile(atPath: dispatcherURL.path) else { return .notRegistered }
        if DorisCLILocator.resolve() == nil { return .missingCLI }
        return .registered
    }

    // MARK: - Register

    public func register() async throws {
        guard let cliPath = DorisCLILocator.resolve() else {
            throw IntegrationError.cliNotInstalled
        }
        let fm = FileManager.default

        // Make sure ~/.codex exists (Codex creates it, but be defensive
        // so registering before first Codex launch still works).
        try? fm.createDirectory(at: Self.codexHomeURL,
                                withIntermediateDirectories: true)

        // 1) Write / refresh the dispatcher. Done first so that even on
        //    an idempotent re-register a moved CLI path gets baked in.
        let script = Self.generateDispatcher(cliPath: cliPath)
        do {
            try script.write(to: dispatcherURL, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: dispatcherURL.path, underlying: error)
        }
        try? fm.setAttributes([.posixPermissions: 0o755],
                              ofItemAtPath: dispatcherURL.path)

        // 2) Wire config.toml's `notify` to the dispatcher.
        let configExists = fm.fileExists(atPath: configURL.path)
        let originalPerms = (try? fm.attributesOfItem(atPath: configURL.path))?[.posixPermissions] as? NSNumber
        let current = configExists
            ? ((try? String(contentsOf: configURL, encoding: .utf8)) ?? "")
            : ""

        // Already wired (dispatcher referenced anywhere in the chain)?
        // The dispatcher was just refreshed above, so leave config.toml
        // untouched — re-writing it would fight the Codex app's
        // previous-notify absorption.
        if current.contains(Self.dispatcherFilename) { return }

        // Back up whatever notify line exists today, so unregister can
        // restore the user's prior setup exactly.
        let originalNotify = Self.firstTopLevelNotifyLine(in: current)
        let backup = originalNotify ?? Self.noOriginalMarker
        try? backup.write(to: backupURL, atomically: true, encoding: .utf8)

        let newLine = "notify = [\(Self.tomlString(dispatcherURL.path))]"
        let updated = Self.upsertNotifyLine(in: current, newLine: newLine)
        do {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: configURL.path, underlying: error)
        }
        // Preserve the original file mode (Codex writes config.toml 0600);
        // a fresh file we created stays private too.
        let mode = originalPerms?.intValue ?? 0o600
        try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: configURL.path)
    }

    // MARK: - Unregister

    public func unregister() async throws {
        let fm = FileManager.default
        defer {
            // Always drop our artifacts, even if the config edit below
            // short-circuits.
            try? fm.removeItem(at: dispatcherURL)
            try? fm.removeItem(at: backupURL)
        }
        guard fm.fileExists(atPath: configURL.path),
              let current = try? String(contentsOf: configURL, encoding: .utf8),
              current.contains(Self.dispatcherFilename) else {
            return // nothing of ours in the config
        }
        let originalPerms = (try? fm.attributesOfItem(atPath: configURL.path))?[.posixPermissions] as? NSNumber
        let backup = (try? String(contentsOf: backupURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let updated: String
        if let backup, !backup.isEmpty, backup != Self.noOriginalMarker {
            // Restore the user's prior notify line verbatim.
            updated = Self.upsertNotifyLine(in: current, newLine: backup)
        } else {
            // There was no prior notify — remove the line entirely.
            updated = Self.removeNotifyLine(in: current)
        }
        do {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: configURL.path, underlying: error)
        }
        if let mode = originalPerms?.intValue {
            try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: configURL.path)
        }
    }

    // MARK: - Dispatcher script

    /// Build the dispatcher. It fires the Doris banner and nothing else
    /// (see the type doc for why it must not forward).
    static func generateDispatcher(cliPath: String) -> String {
        let title = localizedTitle()
        return """
        #!/bin/bash
        \(beginMarker)
        # Managed by Doris. Regenerated whenever you (re-)register the
        # Codex integration from Doris Settings — do not edit by hand.
        #
        # Codex invokes its `notify` program once per turn completion.
        # On builds with the computer-use feature the Codex app keeps
        # its own notifier upstream of us via --previous-notify, so this
        # script must NOT call back into it. It only fires Doris.
        #
        # Firing is unconditional: Codex only calls `notify` on turn
        # completion, so there is no event type to filter on. The JSON
        # payload arrives as "$@" and is intentionally ignored.

        DORIS_CLI="\(cliPath)"

        if [ -x "$DORIS_CLI" ]; then
            "$DORIS_CLI" notify \\
                --title '\(title)' \\
                --source codex \\
                --level reminder \\
                --click-url 'doris://main' >/dev/null 2>&1 &
        fi

        exit 0
        \(endMarker)
        """
    }

    /// Title in the user's current language. Mirrors
    /// ClaudeCodeIntegration: reads the UserDefaults key DorisUI's
    /// LanguageSettings writes, so DorisCore stays UI-independent.
    private static func localizedTitle() -> String {
        let mode = UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh"
        return mode == "en" ? "Codex task complete" : "Codex 任务完成"
    }

    // MARK: - TOML notify-line surgery

    /// Index of the first **top-level** `notify = …` assignment, or nil.
    /// "Top-level" = appears before the first `[table]` header, since
    /// TOML top-level keys must precede any table.
    static func topLevelNotifyIndex(_ lines: [String]) -> Int? {
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { return nil }      // entered a table — stop
            if isNotifyAssignment(t) { return i }
        }
        return nil
    }

    /// True if `trimmed` is a `notify = …` assignment (not `notify_x`,
    /// not a comment).
    static func isNotifyAssignment(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("notify") else { return false }
        let rest = trimmed.dropFirst("notify".count)
            .drop(while: { $0 == " " || $0 == "\t" })
        return rest.first == "="
    }

    static func firstTopLevelNotifyLine(in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let idx = topLevelNotifyIndex(lines) else { return nil }
        return lines[idx]
    }

    /// Replace the first top-level notify line with `newLine`. If none
    /// exists, insert it just before the first `[table]` header (or
    /// append if the file has no tables).
    static func upsertNotifyLine(in text: String, newLine: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let idx = topLevelNotifyIndex(lines) {
            lines[idx] = newLine
            return lines.joined(separator: "\n")
        }
        if let secIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        }) {
            lines.insert(newLine, at: secIdx)
            return lines.joined(separator: "\n")
        }
        var result = text
        if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
        result += newLine + "\n"
        return result
    }

    /// Remove the first top-level notify line (if any).
    static func removeNotifyLine(in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let idx = topLevelNotifyIndex(lines) {
            lines.remove(at: idx)
        }
        return lines.joined(separator: "\n")
    }

    /// Render a string as a TOML basic string (double-quoted, escaped).
    static func tomlString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

#endif // os(macOS)
