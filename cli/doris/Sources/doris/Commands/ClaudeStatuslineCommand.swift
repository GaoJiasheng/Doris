import ArgumentParser
import Foundation
import DorisIPC

/// Claude Code status-line command. Claude Code invokes the configured
/// `statusLine` command on each render and pipes session JSON on stdin —
/// which (on Pro/Max subscriptions, after the first response of a session)
/// includes `rate_limits.five_hour` / `seven_day` with `used_percentage` +
/// `resets_at`. That's the only supported way to read the real subscription
/// quota locally (what `/usage` shows), so Doris taps it here:
///   • persists the rate limits to the App-Group store for the app to read,
///   • prints a compact, useful status line (model · quota · cost) to stdout.
///
/// Fast + side-effect-free beyond one small file write — it runs on every
/// status refresh, so it never launches the app or enqueues IPC.
struct ClaudeStatuslineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-statusline",
        abstract: "Render the Claude Code status line and capture rate-limit quota for Doris."
    )

    func run() async throws {
        let data = Self.readStdin()
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        Self.persistQuota(from: obj)
        FileHandle.standardOutput.write(Data(Self.render(obj).utf8))
    }

    // MARK: stdin

    private static func readStdin() -> Data {
        var data = Data()
        let h = FileHandle.standardInput
        while true {
            let chunk = h.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    // MARK: persist quota for the app

    private static func persistQuota(from obj: [String: Any]) {
        guard let rl = obj["rate_limits"] as? [String: Any], !rl.isEmpty else { return }
        guard let container = try? IPCDirectory.containerURL() else { return }
        let dir = container.appendingPathComponent("Store", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [String: Any] = ["rate_limits": rl]
        out["capturedAt"] = ISO8601DateFormatter().string(from: Date())
        if let model = (obj["model"] as? [String: Any])?["display_name"] as? String { out["model"] = model }
        if let cost = (obj["cost"] as? [String: Any])?["total_cost_usd"] as? Double { out["sessionCostUSD"] = cost }
        guard let data = try? JSONSerialization.data(withJSONObject: out) else { return }
        try? data.write(to: dir.appendingPathComponent("claude-quota.json"), options: .atomic)
    }

    // MARK: render the line

    private static func render(_ obj: [String: Any]) -> String {
        var parts: [String] = []
        if let model = (obj["model"] as? [String: Any])?["display_name"] as? String {
            parts.append("◐ \(model)")
        }
        if let rl = obj["rate_limits"] as? [String: Any] {
            if let r = remaining(rl["five_hour"]) { parts.append("5h \(r)%") }
            if let r = remaining(rl["seven_day"]) { parts.append("7d \(r)%") }
        }
        if let cost = (obj["cost"] as? [String: Any])?["total_cost_usd"] as? Double, cost > 0 {
            parts.append(String(format: "$%.2f", cost))
        }
        return parts.joined(separator: "  ")
    }

    private static func remaining(_ any: Any?) -> Int? {
        guard let d = any as? [String: Any] else { return nil }
        let used = (d["used_percentage"] as? Double)
            ?? (d["used_percentage"] as? NSNumber)?.doubleValue
            ?? (d["used_percentage"] as? Int).map(Double.init)
        guard let used else { return nil }
        return max(0, min(100, Int((100 - used).rounded())))
    }
}
