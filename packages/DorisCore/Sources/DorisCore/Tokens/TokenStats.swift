#if os(macOS)

import Foundation

public struct TokenTotals: Sendable, Equatable {
    public var input = 0, output = 0, cacheCreate = 0, cacheRead = 0, reasoning = 0
    public var calls = 0
    public var cost = 0.0
    /// input + output + cacheCreate + reasoning (excludes cheap cache reads).
    public var billable: Int { input + output + cacheCreate + reasoning }
    public var total: Int { billable + cacheRead }
}

/// Pure aggregation over `TokenUsageDaily` rows (the bounded rollup table
/// the views `@Query`). No SwiftData context needed — views pass their
/// queried rows in, so results stay live.
public enum TokenStats {
    public enum Range: CaseIterable, Sendable {
        case today, last7, last30, all
        public var title: String {
            switch self {
            case .today: return "Today"
            case .last7: return "7d"
            case .last30: return "30d"
            case .all: return "All"
            }
        }
        /// Inclusive lower bound (start of local day), or nil for all-time.
        public func cutoff(now: Date = Date(), calendar: Calendar = .current) -> Date? {
            let sod = calendar.startOfDay(for: now)
            switch self {
            case .today: return sod
            case .last7:  return calendar.date(byAdding: .day, value: -6, to: sod)
            case .last30: return calendar.date(byAdding: .day, value: -29, to: sod)
            case .all:    return nil
            }
        }
    }

    private static func inRange(_ rows: [TokenUsageDaily], _ range: Range, now: Date) -> [TokenUsageDaily] {
        guard let cutoff = range.cutoff(now: now) else { return rows }
        return rows.filter { $0.day >= cutoff }
    }

    private static func sum(_ rows: [TokenUsageDaily]) -> TokenTotals {
        var t = TokenTotals()
        for r in rows {
            t.input += r.inputTokens; t.output += r.outputTokens
            t.cacheCreate += r.cacheCreateTokens; t.cacheRead += r.cacheReadTokens
            t.reasoning += r.reasoningTokens; t.calls += r.callCount; t.cost += r.costUSD
        }
        return t
    }

    public static func totals(_ rows: [TokenUsageDaily], _ range: Range, now: Date = Date()) -> TokenTotals {
        sum(inRange(rows, range, now: now))
    }

    /// Per-tool totals in a range, sorted by billable tokens desc.
    public static func byTool(_ rows: [TokenUsageDaily], _ range: Range, now: Date = Date()) -> [(TokenTool, TokenTotals)] {
        var map: [TokenTool: [TokenUsageDaily]] = [:]
        for r in inRange(rows, range, now: now) { map[r.tool, default: []].append(r) }
        return map.map { ($0.key, sum($0.value)) }.sorted { $0.1.billable > $1.1.billable }
    }

    /// Per-model totals in a range, sorted by billable tokens desc.
    public static func byModel(_ rows: [TokenUsageDaily], _ range: Range, now: Date = Date()) -> [(String, TokenTotals)] {
        var map: [String: [TokenUsageDaily]] = [:]
        for r in inRange(rows, range, now: now) { map[r.model, default: []].append(r) }
        return map.map { ($0.key, sum($0.value)) }.sorted { $0.1.billable > $1.1.billable }
    }

    /// Per-day billable + cost for the last `days` days (oldest→newest),
    /// filling gaps with zero so the chart has a continuous axis.
    public static func trend(_ rows: [TokenUsageDaily], days: Int, now: Date = Date(),
                             calendar: Calendar = .current) -> [(day: Date, billable: Int, cost: Double)] {
        let sod = calendar.startOfDay(for: now)
        var byDay: [Date: (Int, Double)] = [:]
        for r in rows {
            let d = calendar.startOfDay(for: r.day)
            let prev = byDay[d] ?? (0, 0)
            byDay[d] = (prev.0 + r.billableTokens, prev.1 + r.costUSD)
        }
        var out: [(Date, Int, Double)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let d = calendar.date(byAdding: .day, value: -offset, to: sod) else { continue }
            let v = byDay[d] ?? (0, 0)
            out.append((d, v.0, v.1))
        }
        return out
    }
}

#endif
