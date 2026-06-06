// The whole integrations layer is macOS-only — Claude Code, Codex,
// etc. integrations target the desktop versions of those apps
// (write to ~/.claude/settings.json, install shell wrappers, etc.).
// iOS has no analogue and lacks `homeDirectoryForCurrentUser`
// anyway, so we compile this entire module out on iOS to keep
// DorisCore cross-platform.
#if os(macOS)

import Foundation
import Darwin
import DorisIPC

/// The user's **real** home directory, bypassing App Sandbox container
/// redirection. Inside a sandboxed app `homeDirectoryForCurrentUser` /
/// `NSHomeDirectory()` return the container (`~/Library/Containers/<id>/
/// Data`), so writing `~/.claude` / `~/.codex` there lands in the jail
/// and never reaches the files Claude Code / Codex actually read.
/// `getpwuid` reports the true home (`/Users/<you>`) even under the
/// sandbox; access is granted by the `temporary-exception.files.
/// home-relative-path` entitlements for `/.claude/` and `/.codex/`.
func integrationsRealHome() -> URL {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
        let path = String(cString: dir)
        if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

/// One pluggable "send your task-done notifications through Doris"
/// integration with an external AI app (Claude Code, Codex, future
/// Trae/Cursor/Feishu/…).
///
/// The UI binds against this protocol uniformly: every Integrations
/// row shows status + an action button, regardless of whether the
/// app supports automatic hook injection or requires manual setup.
/// Adding a new integration is just dropping in another conforming
/// type and appending it to `IntegrationsRegistry.providers`.
public protocol IntegrationProvider: Sendable {
    /// Stable identifier used in logs / saved status. Never localized.
    var id: String { get }

    /// English brand name shown in the UI. Brand names aren't translated.
    var displayName: String { get }

    /// One-line English description; the SettingsUI also pairs each
    /// provider with a Chinese variant via its own L() table so we
    /// don't bring localization into the model layer.
    var summary: String { get }

    /// SF Symbol used for the row icon. Apps with their own bundle
    /// icon could later swap this for a real asset.
    var iconSymbol: String { get }

    /// What kind of notification this app fires (e.g. .claudeCode,
    /// .codex, .chatgpt). The registration writes this as the
    /// `source` field so notifications are colored / icon'd correctly.
    var sourceKind: SourceKind { get }

    /// URL opened when the user clicks the resulting notification.
    /// e.g. claude:// / chatgpt:// / codex://.
    var clickURL: URL? { get }

    /// Whether automatic register / unregister is implemented, the
    /// user has to do it themselves, or the integration is currently
    /// not feasible at all.
    var supportTier: IntegrationSupportTier { get }

    /// Optional URL the UI opens when supportTier == .manual and the
    /// user clicks the "查看教程" link. Can be a Doris-hosted page,
    /// a Notion doc, or a GitHub README anchor.
    var tutorialURL: URL? { get }

    /// Cheap-ish filesystem probe to determine current state. Called
    /// every time the Settings panel appears + after each register /
    /// unregister so the UI reflects truth.
    func currentStatus() async -> IntegrationStatus

    /// Install / write whatever hooks make this app call back into
    /// Doris. Idempotent — calling on an already-registered provider
    /// is a no-op success.
    func register() async throws

    /// Undo what `register()` did. Idempotent — removing already-
    /// absent hooks is a no-op success. Must preserve any other,
    /// non-Doris hooks the user wrote themselves.
    func unregister() async throws
}

/// Coarse capability tier driving UI affordances.
public enum IntegrationSupportTier: String, Sendable {
    /// Doris can read + write the app's config to wire everything up.
    /// Settings shows a "连接" / "解除" toggle.
    case full

    /// Doris can't auto-configure (no hook API, or app is GUI-only),
    /// but the user can wire it up themselves via a Shortcut, a
    /// wrapper script, etc. Settings shows a "查看教程" link.
    case manual

    /// Nothing usable right now. Settings shows a grayed-out row with
    /// a "暂不支持" badge. Kept so the row stays visible and the
    /// product clearly signals "we know this exists".
    case unsupported
}

/// Current state of the integration on this machine.
public enum IntegrationStatus: Equatable, Sendable {
    /// Hook is in place and the CLI it points to is present + executable.
    case registered

    /// No hook found. User can click the action button to install.
    case notRegistered

    /// User wants this but the Doris CLI binary it would call isn't
    /// reachable on disk (wizard never ran, or symlink got nuked).
    /// UI funnels into the install-CLI wizard before retrying.
    case missingCLI

    /// Something went wrong while reading the config file (perms,
    /// malformed JSON, etc.). The string is user-facing.
    case error(String)

    /// Provider explicitly declined to track state — usually paired
    /// with supportTier == .manual or .unsupported.
    case notApplicable
}

/// Errors a register / unregister attempt can surface to the UI. All
/// localized at the call site; the cases just carry context.
public enum IntegrationError: Error, LocalizedError {
    case cliNotInstalled
    case readFailed(path: String, underlying: Error?)
    case writeFailed(path: String, underlying: Error?)
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .cliNotInstalled:
            return "Doris CLI is not installed."
        case .readFailed(let path, let err):
            return "Failed to read \(path): \(err?.localizedDescription ?? "unknown")"
        case .writeFailed(let path, let err):
            return "Failed to write \(path): \(err?.localizedDescription ?? "unknown")"
        case .notSupported:
            return "This integration can't be auto-configured."
        }
    }
}

/// Resolves the absolute path to the `doris` CLI binary on this
/// machine. Used by `register()` implementations to bake an absolute
/// command into hook configs — relying on `$PATH` is fragile inside
/// non-interactive hook shells.
public enum DorisCLILocator {
    /// First match wins:
    ///   1. `/usr/local/bin/doris` (wizard default; survives app moves
    ///      because the symlink target lives inside the bundle, which
    ///      LaunchServices tracks)
    ///   2. `~/.local/bin/doris` (wizard secondary)
    ///   3. `Doris.app/Contents/Resources/doris` (always present once
    ///      Doris is installed, even if the user skipped the wizard)
    public static func resolve() -> String? {
        let fm = FileManager.default
        let candidates: [String] = [
            "/usr/local/bin/doris",
            (fm.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".local/bin/doris"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/doris")
                .path
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}

#endif // os(macOS)
