#if os(macOS)

import Foundation
import DorisIPC

/// ChatGPT desktop integration — pure-GUI client with no public
/// notification callback or hooks surface. Listed in the registry
/// so the UI can clearly communicate "we thought about this; here's
/// the workaround". The tutorial URL walks the user through wiring
/// a macOS Shortcut that fires `open doris://notify?...` when a
/// ChatGPT response arrives (via Focus Filters or manual button).
public struct ChatGPTIntegration: IntegrationProvider {
    public let id = "chatgpt"
    public let displayName = "ChatGPT"
    public let summary = "Trigger via macOS Shortcut → doris:// URL scheme."
    public let iconSymbol = "bubble.left.and.bubble.right.fill"
    public let sourceKind: SourceKind = .chatgpt
    public let clickURL: URL? = URL(string: "chatgpt://")
    public let supportTier: IntegrationSupportTier = .manual
    public let tutorialURL: URL? = URL(string: "https://github.com/GaoJiasheng/khan/blob/main/docs/integrations/chatgpt.md")

    public init() {}

    public func currentStatus() async -> IntegrationStatus { .notApplicable }
    public func register() async throws { throw IntegrationError.notSupported }
    public func unregister() async throws {}
}

#endif // os(macOS)
