#if os(macOS)

import Foundation

/// One parsed model call from a tool's log — a pure value type so adapters
/// stay free of SwiftData. `TokenCollector` converts these into
/// `TokenUsageEvent`/`TokenUsageDaily` rows + computes cost.
public struct TokenSample: Sendable {
    public let tool: TokenTool
    public let model: String
    public let sessionId: String
    /// Stable dedup key (requestId / messageId / sessionId#turn).
    public let dedupKey: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreateTokens: Int
    public let cacheReadTokens: Int
    public let reasoningTokens: Int
    public let serviceTier: String?
    public let ts: Date

    public init(tool: TokenTool, model: String, sessionId: String, dedupKey: String,
                inputTokens: Int, outputTokens: Int, cacheCreateTokens: Int = 0,
                cacheReadTokens: Int = 0, reasoningTokens: Int = 0,
                serviceTier: String? = nil, ts: Date) {
        self.tool = tool
        self.model = model
        self.sessionId = sessionId
        self.dedupKey = dedupKey
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreateTokens = cacheCreateTokens
        self.cacheReadTokens = cacheReadTokens
        self.reasoningTokens = reasoningTokens
        self.serviceTier = serviceTier
        self.ts = ts
    }
}

/// Availability/health of a source, surfaced in the UI as a status row
/// (mirrors `IntegrationSupportTier` semantics for the token side).
public enum TokenSourceStatus: Equatable, Sendable {
    case ok                     // source present + parseable
    case unavailable            // logs/dir/key not found on this machine
    case needsConfig(String)    // present but needs a key / extra grant
    case unsupported(String)    // can't be done yet
    case error(String)
}

/// A pluggable token-usage source. One conforming type per tool; register
/// in `TokenSourceRegistry`. Adapters are pure parsers: given the last
/// cursor, return new samples + the advanced cursor. All filesystem reads
/// use `integrationsRealHome()` to bypass the App Sandbox container.
public protocol TokenSourceAdapter: Sendable {
    var tool: TokenTool { get }
    /// Log directories to FSEvents-watch for near-real-time collection.
    /// Empty for API-only sources (covered by the periodic timer instead).
    var watchPaths: [URL] { get }
    /// Cheap probe for the status row.
    func status() -> TokenSourceStatus
    /// Parse everything new since `cursorJSON` (nil = first run / full
    /// backfill). Returns fresh samples + the cursor to persist. Adapters
    /// own their cursor's JSON shape.
    func collect(cursorJSON: String?) throws -> (samples: [TokenSample], cursorJSON: String)
}

public extension TokenSourceAdapter {
    var watchPaths: [URL] { [] }
    var isAvailable: Bool { if case .ok = status() { return true } else { return false } }
}

#endif
