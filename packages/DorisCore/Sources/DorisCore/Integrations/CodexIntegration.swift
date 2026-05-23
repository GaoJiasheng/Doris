#if os(macOS)

import Foundation
import DorisIPC

/// Codex integration — OpenAI's agentic coding tool. Their CLI /
/// desktop app currently lacks a documented hooks system equivalent
/// to Claude Code's. Until OpenAI exposes one, this provider stays at
/// `.manual` and points the user at a tutorial that explains how to
/// wrap the `codex` command in a shell function that fires
/// `doris notify` on exit.
///
/// Once Codex publishes a hooks API, this provider can flip to
/// `.full` and implement the same kind of upsert ClaudeCodeIntegration
/// does. The rest of the Doris UI doesn't have to change.
public struct CodexIntegration: IntegrationProvider {
    public let id = "codex"
    public let displayName = "Codex"
    public let summary = "Wrap `codex` shell command to fire Doris on exit."
    public let iconSymbol = "terminal"
    public let sourceKind: SourceKind = .codex
    public let clickURL: URL? = URL(string: "codex://")
    public let supportTier: IntegrationSupportTier = .manual
    public let tutorialURL: URL? = URL(string: "https://github.com/GaoJiasheng/khan/blob/main/docs/integrations/codex.md")

    public init() {}

    public func currentStatus() async -> IntegrationStatus { .notApplicable }
    public func register() async throws { throw IntegrationError.notSupported }
    public func unregister() async throws {}
}

#endif // os(macOS)
