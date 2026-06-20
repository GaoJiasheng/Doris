#if os(macOS)

import Foundation

/// All token-usage adapters Doris knows about. Adding a tool = drop a new
/// `TokenSourceAdapter` conformer and append it here (mirrors
/// `IntegrationsRegistry`). Phase 1 ships the two with local logs + sandbox
/// grants; Cursor/Gemini/OpenAI adapters land in Phase 2.
public enum TokenSourceRegistry {
    public static let adapters: [any TokenSourceAdapter] = [
        ClaudeCodeAdapter(),
        CodexAdapter(),
    ]

    public static func adapter(for tool: TokenTool) -> (any TokenSourceAdapter)? {
        adapters.first { $0.tool == tool }
    }
}

#endif
