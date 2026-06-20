// Token-usage monitoring is macOS-only: the data is collected by reading
// local AI-tool logs (~/.claude, ~/.codex, …) which only exist on the
// desktop, and the UI ships on macOS only. The whole module compiles out
// on iOS (mirrors the Integrations layer).
#if os(macOS)

import Foundation
import SwiftData

/// One AI tool whose token usage Doris monitors. Raw values are stable
/// (persisted in the store + settings).
public enum TokenTool: String, CaseIterable, Sendable, Codable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case gemini
    case openai

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .cursor:     return "Cursor"
        case .gemini:     return "Gemini"
        case .openai:     return "OpenAI"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex:      return "chevron.left.forwardslash.chevron.right"
        case .cursor:     return "cursorarrow.rays"
        case .gemini:     return "diamond.fill"
        case .openai:     return "brain"
        }
    }
}

// MARK: - SwiftData models (dedicated local store — see TokenStore)

/// One billable model call, parsed from a tool's local log. Kept raw so we
/// can dedup (by `dedupKey`), drill down, and re-aggregate later. The UI
/// reads `TokenUsageDaily` (fast, bounded); these power dedup + detail.
@Model
public final class TokenUsageEvent {
    /// Stable de-duplication key — Claude Code `requestId`/message id, Codex
    /// `sessionId#turnIndex`. Same key across resumed-session files must not
    /// be counted twice.
    @Attribute(.unique) public var dedupKey: String = ""
    public var toolRaw: String = ""
    public var model: String = ""
    public var sessionId: String = ""
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreateTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var reasoningTokens: Int = 0
    public var serviceTier: String?
    public var costUSD: Double = 0
    public var ts: Date = Date()

    public var tool: TokenTool { TokenTool(rawValue: toolRaw) ?? .claudeCode }
    /// Tokens that count toward "usage" headline (excludes cache reads,
    /// which are cheap/free) — input + output + cacheCreate + reasoning.
    public var billableTokens: Int { inputTokens + outputTokens + cacheCreateTokens + reasoningTokens }
    /// Everything including cache reads — the "raw throughput" number.
    public var totalTokens: Int { billableTokens + cacheReadTokens }

    public init(dedupKey: String, toolRaw: String, model: String, sessionId: String,
                inputTokens: Int, outputTokens: Int, cacheCreateTokens: Int,
                cacheReadTokens: Int, reasoningTokens: Int, serviceTier: String?,
                costUSD: Double, ts: Date) {
        self.dedupKey = dedupKey
        self.toolRaw = toolRaw
        self.model = model
        self.sessionId = sessionId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreateTokens = cacheCreateTokens
        self.cacheReadTokens = cacheReadTokens
        self.reasoningTokens = reasoningTokens
        self.serviceTier = serviceTier
        self.costUSD = costUSD
        self.ts = ts
    }
}

/// Per-day × tool × model rollup — the fast, bounded query surface for the
/// dashboard. Maintained incrementally by `TokenCollector` as events arrive.
@Model
public final class TokenUsageDaily {
    /// "yyyy-MM-dd|tool|model" — upsert key.
    @Attribute(.unique) public var bucketKey: String = ""
    public var day: Date = Date()          // start of local day
    public var toolRaw: String = ""
    public var model: String = ""
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreateTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var reasoningTokens: Int = 0
    public var callCount: Int = 0
    public var costUSD: Double = 0

    public var tool: TokenTool { TokenTool(rawValue: toolRaw) ?? .claudeCode }
    public var billableTokens: Int { inputTokens + outputTokens + cacheCreateTokens + reasoningTokens }
    public var totalTokens: Int { billableTokens + cacheReadTokens }

    public init(bucketKey: String, day: Date, toolRaw: String, model: String) {
        self.bucketKey = bucketKey
        self.day = day
        self.toolRaw = toolRaw
        self.model = model
    }
}

/// Per-source incremental cursor (e.g. per-file byte offsets) so we never
/// re-parse already-ingested log content across launches.
@Model
public final class TokenIngestState {
    @Attribute(.unique) public var sourceId: String = ""
    /// Opaque JSON the adapter (de)serializes itself.
    public var cursorJSON: String = ""
    public var updatedAt: Date = Date()

    public init(sourceId: String, cursorJSON: String = "") {
        self.sourceId = sourceId
        self.cursorJSON = cursorJSON
    }
}

#endif
