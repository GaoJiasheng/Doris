#if os(macOS)

import Foundation
import SwiftData
import DorisIPC

/// One subscription rate-limit window for a tool.
public struct QuotaWindow: Identifiable, Sendable {
    public var id: String { "\(toolRaw)-\(label)" }
    public let toolRaw: String
    public let toolName: String
    public let label: String            // "5h" / "Weekly"
    /// 0…100 used; nil when unknown (Claude estimate with no configured cap).
    public let usedPercent: Double?
    /// Tokens used in the window (Claude estimate display when % unknown).
    public let usedTokens: Int?
    public let resetsAt: Date?
    public let isEstimate: Bool
    public let planType: String?

    public var remainingPercent: Double? { usedPercent.map { max(0, 100 - $0) } }
}

/// Produces quota windows. Codex exposes authoritative `rate_limits` in its
/// rollouts (real %, reset, plan). Claude Code persists no quota locally, so
/// its 5-hour window is *estimated* from event timestamps (reset is solid;
/// % only if the user configures a plan cap).
public enum QuotaReader {
    public static func windows(container: ModelContainer?, claudeCap: Int) -> [QuotaWindow] {
        var out: [QuotaWindow] = []
        out += codexWindows()
        if let container { out += claudeWindows(container: container, cap: claudeCap) }
        return out
    }

    // MARK: Codex (authoritative)

    static func codexWindows() -> [QuotaWindow] {
        let root = integrationsRealHome().appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = JSONLScanner.jsonlFiles(under: root)
            .filter { $0.lastPathComponent.hasPrefix("rollout-") }
            .sorted { (mtime($0) ?? .distantPast) > (mtime($1) ?? .distantPast) }
        // Newest rollouts first; use the most recent file that has a
        // non-null rate_limits payload.
        for file in files.prefix(4) {
            guard let rl = lastRateLimits(in: file) else { continue }
            var out: [QuotaWindow] = []
            let plan = rl["plan_type"] as? String
            if let w = window(from: rl["primary"], tool: .codex, plan: plan) { out.append(w) }
            if let w = window(from: rl["secondary"], tool: .codex, plan: plan) { out.append(w) }
            if !out.isEmpty { return out }
        }
        return []
    }

    private static func window(from any: Any?, tool: TokenTool, plan: String?) -> QuotaWindow? {
        guard let d = any as? [String: Any] else { return nil }
        let used = (d["used_percent"] as? Double) ?? (d["used_percent"] as? NSNumber)?.doubleValue ?? 0
        let mins = (d["window_minutes"] as? Int) ?? (d["window_minutes"] as? NSNumber)?.intValue ?? 0
        let reset: Date? = (d["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return QuotaWindow(
            toolRaw: tool.rawValue, toolName: tool.displayName,
            label: windowLabel(minutes: mins),
            usedPercent: used, usedTokens: nil, resetsAt: reset,
            isEstimate: false, planType: plan)
    }

    private static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 0: return "window"
        case ..<60: return "\(minutes)m"
        case ..<1440: return "\(minutes / 60)h"
        default: return "\(minutes / 1440)d"
        }
    }

    /// Read a rollout and return the LAST non-null `rate_limits` dict.
    private static func lastRateLimits(in file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var latest: [String: Any]?
        for line in text.split(separator: "\n") {
            guard line.contains("rate_limits") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let rl = payload["rate_limits"] as? [String: Any] else { continue }
            latest = rl
        }
        return latest
    }

    private static func mtime(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Claude Code (estimated 5-hour window)

    static func claudeWindows(container: ModelContainer, cap: Int) -> [QuotaWindow] {
        // Prefer the REAL quota captured by the status-line command, if fresh.
        if let real = claudeRealWindows() { return real }
        // Otherwise estimate from the 5-hour rolling window.
        let ctx = ModelContext(container)
        let now = Date()
        let cutoff = now.addingTimeInterval(-5 * 3600)
        let cc = TokenTool.claudeCode.rawValue
        var fd = FetchDescriptor<TokenUsageEvent>(
            predicate: #Predicate { $0.toolRaw == cc && $0.ts >= cutoff },
            sortBy: [SortDescriptor(\.ts, order: .forward)])
        fd.propertiesToFetch = [\.ts, \.inputTokens, \.outputTokens, \.cacheCreateTokens, \.reasoningTokens]
        let events = (try? ctx.fetch(fd)) ?? []

        let cal = Calendar.current
        var blockStart: Date?
        var used = 0
        if let first = events.first {
            blockStart = cal.dateInterval(of: .hour, for: first.ts)?.start ?? first.ts
            for e in events { used += e.billableTokens }
        }
        let reset = blockStart.map { $0.addingTimeInterval(5 * 3600) }
        let pct: Double? = cap > 0 ? min(100, Double(used) / Double(cap) * 100) : nil
        return [QuotaWindow(
            toolRaw: cc, toolName: TokenTool.claudeCode.displayName,
            label: "5h", usedPercent: pct, usedTokens: used,
            resetsAt: reset, isEstimate: true, planType: nil)]
    }

    /// Real Claude quota captured by the status-line command into the App
    /// Group (`Store/claude-quota.json`). nil if absent / stale (>6h, i.e. no
    /// recent Claude Code activity) so the caller falls back to the estimate.
    static func claudeRealWindows() -> [QuotaWindow]? {
        guard let container = try? IPCDirectory.containerURL() else { return nil }
        let url = container.appendingPathComponent("Store/claude-quota.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capturedStr = obj["capturedAt"] as? String,
              let captured = ISO8601DateFormatter().date(from: capturedStr),
              Date().timeIntervalSince(captured) < 6 * 3600,
              let rl = obj["rate_limits"] as? [String: Any] else { return nil }
        var out: [QuotaWindow] = []
        if let w = realWindow(rl["five_hour"], label: "5h") { out.append(w) }
        if let w = realWindow(rl["seven_day"], label: L7) { out.append(w) }
        return out.isEmpty ? nil : out
    }

    private static let L7 = "7d"

    private static func realWindow(_ any: Any?, label: String) -> QuotaWindow? {
        guard let d = any as? [String: Any] else { return nil }
        let used = (d["used_percentage"] as? Double)
            ?? (d["used_percentage"] as? NSNumber)?.doubleValue
            ?? (d["used_percentage"] as? Int).map(Double.init)
        guard let used else { return nil }
        let iso = ISO8601DateFormatter()
        let reset = (d["resets_at"] as? String).flatMap { iso.date(from: $0) }
        return QuotaWindow(
            toolRaw: TokenTool.claudeCode.rawValue, toolName: TokenTool.claudeCode.displayName,
            label: label, usedPercent: used, usedTokens: nil,
            resetsAt: reset, isEstimate: false, planType: nil)
    }
}

#endif
