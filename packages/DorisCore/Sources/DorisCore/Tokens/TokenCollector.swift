#if os(macOS)

import Foundation
import SwiftData

/// Runs the enabled adapters, deduplicates, and folds new samples into the
/// raw-event table + daily rollups. Builds its own `ModelContext` so it can
/// run off the main actor (the first run backfills the full history).
public final class TokenCollector: @unchecked Sendable {
    private let container: ModelContainer
    public init(container: ModelContainer) { self.container = container }

    public struct Summary: Sendable {
        public var newEvents: Int = 0
        public var byTool: [String: Int] = [:]
    }

    /// Parse everything new from `tools` and persist. Safe to call from a
    /// background task; cheap when there's nothing new (cursors short-circuit).
    @discardableResult
    public func collect(tools: Set<TokenTool>) -> Summary {
        let ctx = ModelContext(container)

        // Existing dedup keys (cross-run dedup — resumed sessions re-emit old
        // requestIds). propertiesToFetch keeps this light.
        var seen = Set<String>()
        var keyFetch = FetchDescriptor<TokenUsageEvent>()
        keyFetch.propertiesToFetch = [\.dedupKey]
        if let existing = try? ctx.fetch(keyFetch) { for e in existing { seen.insert(e.dedupKey) } }

        var dailyCache: [String: TokenUsageDaily] = [:]
        let cal = Calendar.current
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"; dayFmt.calendar = cal; dayFmt.timeZone = cal.timeZone

        func daily(_ key: String, _ day: Date, _ tool: TokenTool, _ model: String) -> TokenUsageDaily {
            if let d = dailyCache[key] { return d }
            var fd = FetchDescriptor<TokenUsageDaily>(predicate: #Predicate { $0.bucketKey == key })
            fd.fetchLimit = 1
            if let found = try? ctx.fetch(fd).first { dailyCache[key] = found; return found }
            let d = TokenUsageDaily(bucketKey: key, day: day, toolRaw: tool.rawValue, model: model)
            ctx.insert(d); dailyCache[key] = d; return d
        }

        var summary = Summary()
        var sinceSave = 0

        for adapter in TokenSourceRegistry.adapters where tools.contains(adapter.tool) {
            guard adapter.isAvailable else { continue }
            let sourceId = adapter.tool.rawValue
            var stFetch = FetchDescriptor<TokenIngestState>(predicate: #Predicate { $0.sourceId == sourceId })
            stFetch.fetchLimit = 1
            let state: TokenIngestState
            if let found = try? ctx.fetch(stFetch).first {
                state = found
            } else {
                state = TokenIngestState(sourceId: sourceId); ctx.insert(state)
            }

            guard let result = try? adapter.collect(cursorJSON: state.cursorJSON.isEmpty ? nil : state.cursorJSON)
            else { continue }

            for s in result.samples where !seen.contains(s.dedupKey) {
                seen.insert(s.dedupKey)
                let cost = TokenPricing.cost(model: s.model, input: s.inputTokens, output: s.outputTokens,
                                             cacheCreate: s.cacheCreateTokens, cacheRead: s.cacheReadTokens,
                                             reasoning: s.reasoningTokens)
                ctx.insert(TokenUsageEvent(
                    dedupKey: s.dedupKey, toolRaw: s.tool.rawValue, model: s.model, sessionId: s.sessionId,
                    inputTokens: s.inputTokens, outputTokens: s.outputTokens,
                    cacheCreateTokens: s.cacheCreateTokens, cacheReadTokens: s.cacheReadTokens,
                    reasoningTokens: s.reasoningTokens, serviceTier: s.serviceTier, costUSD: cost, ts: s.ts))

                let bkey = "\(dayFmt.string(from: s.ts))|\(s.tool.rawValue)|\(s.model)"
                let d = daily(bkey, cal.startOfDay(for: s.ts), s.tool, s.model)
                d.inputTokens += s.inputTokens; d.outputTokens += s.outputTokens
                d.cacheCreateTokens += s.cacheCreateTokens; d.cacheReadTokens += s.cacheReadTokens
                d.reasoningTokens += s.reasoningTokens; d.callCount += 1; d.costUSD += cost

                summary.newEvents += 1
                summary.byTool[s.tool.rawValue, default: 0] += 1
                sinceSave += 1
                if sinceSave >= 5000 {            // bound memory during backfill
                    try? ctx.save(); dailyCache.removeAll(); sinceSave = 0
                }
            }
            state.cursorJSON = result.cursorJSON
            state.updatedAt = Date()
        }
        try? ctx.save()
        return summary
    }
}

#endif
