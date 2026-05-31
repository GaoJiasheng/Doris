#if os(macOS)

import Foundation
import DorisIPC

/// Codex integration — OpenAI's agentic coding tool.
///
/// Codex has no documented hooks API (vs. Claude Code's
/// `~/.claude/settings.json` hook injection). The next best thing is
/// a **shell wrapper**: a `codex()` function in the user's shell rc
/// file that calls `command codex "$@"`, captures the exit code, and
/// fires `doris notify` on completion. Same end-user effect as a
/// proper hook (banner pops when a long codex task finishes), just
/// achieved at shell-function granularity instead of inside the
/// app.
///
/// Wrapper block shape (zsh / bash variant):
/// ```bash
/// # >>> doris-codex-integration >>>
/// codex() {
///     command codex "$@"
///     local exit_code=$?
///     if [ $exit_code -eq 0 ]; then
///         /usr/local/bin/doris notify --title 'Codex 任务完成' \
///             --source codex --level reminder --click-url 'doris://main' \
///             >/dev/null 2>&1
///     else
///         /usr/local/bin/doris notify --title 'Codex 任务完成 (失败)' \
///             --body "exit $exit_code" --source codex --level critical \
///             --click-url 'doris://main' >/dev/null 2>&1
///     fi
///     return $exit_code
/// }
/// # <<< doris-codex-integration <<<
/// ```
///
/// Detection / cleanup uses the begin/end marker lines so the block
/// can be upserted in place without parsing the surrounding rc file.
/// Any other content in the rc file is preserved untouched.
public struct CodexIntegration: IntegrationProvider {
    public let id = "codex"
    public let displayName = "Codex"
    public let summary = "Wrap `codex` shell command to fire Doris on exit."
    public let iconSymbol = "terminal"
    public let sourceKind: SourceKind = .codex
    public let clickURL: URL? = URL(string: "codex://")
    public let supportTier: IntegrationSupportTier = .full
    public let tutorialURL: URL? = URL(string: "https://github.com/GaoJiasheng/khan/blob/main/docs/integrations/codex.md")

    /// Block-delimiter markers. Begin/end shapes (vs. a single-line
    /// marker like ClaudeCode uses) because the wrapper is multi-line —
    /// we need to know where to cut.
    static let beginMarker = "# >>> doris-codex-integration >>>"
    static let endMarker   = "# <<< doris-codex-integration <<<"

    /// Which interactive shell rc file to touch. Apple's docs say
    /// `$SHELL` reflects the user's *login* shell which is also their
    /// default Terminal.app shell on macOS — good enough as a fast
    /// detection without parsing `/etc/passwd`.
    enum Shell {
        case zsh
        case bash
        case fish

        /// rc filename relative to the user's home dir.
        var rcRelativePath: String {
            switch self {
            case .zsh:  return ".zshrc"
            case .bash: return ".bashrc"
            case .fish: return ".config/fish/config.fish"
            }
        }
    }

    private static func detectShell() -> Shell {
        let s = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        if s.contains("zsh")  { return .zsh }
        if s.contains("fish") { return .fish }
        return .bash
    }

    private var rcURL: URL {
        let shell = Self.detectShell()
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(shell.rcRelativePath)
    }

    public init() {}

    public func currentStatus() async -> IntegrationStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rcURL.path) else { return .notRegistered }
        guard let text = try? String(contentsOf: rcURL, encoding: .utf8) else {
            return .error("Couldn't read \(rcURL.lastPathComponent)")
        }
        if text.contains(Self.beginMarker) {
            // Block is present; verify the CLI it points at still resolves.
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
        let shell = Self.detectShell()
        let block = Self.generateBlock(cliPath: cliPath, shell: shell)
        let url = rcURL

        // Create the parent dir if needed (fish nests under ~/.config).
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true
        )

        let existing: String
        if FileManager.default.fileExists(atPath: url.path) {
            existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        } else {
            existing = ""
        }
        // Upsert: drop the old block (if any) then append the fresh one.
        // Refreshing in place is important for cases where the CLI path
        // moved (e.g. user re-installed Doris and the symlink target
        // changed).
        var cleaned = Self.removeBlock(from: existing)
        // Ensure a separating newline before our block.
        if !cleaned.isEmpty && !cleaned.hasSuffix("\n") {
            cleaned += "\n"
        }
        if !cleaned.isEmpty {
            cleaned += "\n"
        }
        let updated = cleaned + block + "\n"
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: url.path, underlying: error)
        }
    }

    public func unregister() async throws {
        let url = rcURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            // Nothing readable to mutate — treat as idempotent success.
            return
        }
        let cleaned = Self.removeBlock(from: existing)
        do {
            try cleaned.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw IntegrationError.writeFailed(path: url.path, underlying: error)
        }
    }

    // MARK: - Block string ops

    /// Strip every line between (and including) the begin/end markers.
    /// Operates line-by-line so we tolerate stray whitespace around
    /// the markers without depending on exact-match in regex form.
    static func removeBlock(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var inBlock = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == beginMarker { inBlock = true;  continue }
            if trimmed == endMarker   { inBlock = false; continue }
            if !inBlock { result.append(line) }
        }
        // Strip trailing blank lines that the removed block left behind,
        // so re-registering doesn't accumulate blank rows over time.
        while let last = result.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    /// Build the wrapper block for the given shell. Single-quoted
    /// string args keep the body safe from shell expansion regardless
    /// of how the rc file is sourced.
    static func generateBlock(cliPath: String, shell: Shell) -> String {
        let quotedPath = cliPath.contains(" ") ? "'\(cliPath)'" : cliPath
        let title = localizedTitle()
        let titleFail = localizedTitleFailure()
        switch shell {
        case .zsh, .bash:
            return """
            \(beginMarker)
            codex() {
                command codex "$@"
                local exit_code=$?
                if [ $exit_code -eq 0 ]; then
                    \(quotedPath) notify --title '\(title)' --source codex --level reminder --click-url 'doris://main' >/dev/null 2>&1
                else
                    \(quotedPath) notify --title '\(titleFail)' --body "exit $exit_code" --source codex --level critical --click-url 'doris://main' >/dev/null 2>&1
                fi
                return $exit_code
            }
            \(endMarker)
            """
        case .fish:
            // Fish syntax differs: `function ... end`, `$argv`, `$status`.
            return """
            \(beginMarker)
            function codex
                command codex $argv
                set -l exit_code $status
                if test $exit_code -eq 0
                    \(quotedPath) notify --title '\(title)' --source codex --level reminder --click-url 'doris://main' >/dev/null 2>&1
                else
                    \(quotedPath) notify --title '\(titleFail)' --body "exit $exit_code" --source codex --level critical --click-url 'doris://main' >/dev/null 2>&1
                end
                return $exit_code
            end
            \(endMarker)
            """
        }
    }

    /// Pick titles for the user's current language. Mirrors the
    /// ClaudeCodeIntegration approach — reads the UserDefaults key
    /// DorisUI's LanguageSettings writes to, so DorisCore stays
    /// independent of the UI module.
    private static func localizedTitle() -> String {
        let mode = UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh"
        return mode == "en" ? "Codex task complete" : "Codex 任务完成"
    }

    private static func localizedTitleFailure() -> String {
        let mode = UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh"
        return mode == "en" ? "Codex task failed" : "Codex 任务失败"
    }
}

#endif // os(macOS)
