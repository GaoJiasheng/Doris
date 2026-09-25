import Foundation

/// Codex's `notify` program, when `~/.codex/doris-notify-dispatch.sh` is a
/// symlink to this binary — how Doris wires Codex since 1.8.3.
///
/// The dispatcher used to be a shell script the app wrote. Files a
/// sandboxed app writes carry a hard quarantine, and macOS refuses to exec
/// a hard-quarantined script ("operation not permitted"), so a dispatcher
/// written by the shipping app could never run. A symlink resolves to this
/// signed binary inside the app bundle, which isn't quarantined. What the
/// banner says lives in `~/.doris/codex-notify.json`, written by the app —
/// a quarantined data file is harmless.
enum CodexNotifyDispatch {
    static let invocationName = "doris-notify-dispatch.sh"

    static func matches(_ argv0: String?) -> Bool {
        guard let argv0 else { return false }
        return (argv0 as NSString).lastPathComponent == invocationName
    }

    private struct Settings: Decodable {
        var title: String?
        var level: String?
        var clickURL: String?
    }

    /// `doris notify` arguments for a Codex turn completion. Codex's JSON
    /// payload (its last argument) carries nothing the banner uses, so it
    /// is ignored — as the script version did.
    static func notifyArguments() -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".doris/codex-notify.json")
        let s = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
        return ["--title", s?.title ?? "Codex 任务完成",
                "--source", "codex",
                "--level", s?.level ?? "reminder",
                "--click-url", s?.clickURL ?? "doris://main",
                "--quiet"]
    }
}
