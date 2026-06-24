#if os(macOS)

import Foundation
import SwiftData
import DorisIPC

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

        // ── One-time fix (codexDedupFixV2) ──────────────────────────────
        // The Codex dedup key used a per-collect sequence number that reset
        // every collect, so re-scanning a still-growing session produced
        // colliding keys and the new turns were dropped as "duplicates" — only
        // the first few turns of long sessions were ever recorded (a 24M-token
        // session showed ~0.6M). The key is now content-stable; wipe the old
        // codex rows + reset its ingest cursor so the next scan re-reads every
        // codex rollout from the top and recovers the lost history.
        let mdefaults = UserDefaults(suiteName: DorisIdentifiers.appGroup) ?? .standard
        let migFlag = "doris.tokens.codexDedupFixV2"
        if !mdefaults.bool(forKey: migFlag) {
            let codexRaw = TokenTool.codex.rawValue
            try? ctx.delete(model: TokenUsageEvent.self, where: #Predicate { $0.toolRaw == codexRaw })
            try? ctx.delete(model: TokenUsageDaily.self, where: #Predicate { $0.toolRaw == codexRaw })
            var stFd = FetchDescriptor<TokenIngestState>(predicate: #Predicate { $0.sourceId == codexRaw })
            stFd.fetchLimit = 1
            if let st = try? ctx.fetch(stFd).first { ctx.delete(st) }
            try? ctx.save()
            mdefaults.set(true, forKey: migFlag)
        }

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
