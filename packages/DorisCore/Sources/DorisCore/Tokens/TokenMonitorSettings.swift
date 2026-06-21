#if os(macOS)

import Foundation
import Combine
import DorisIPC

/// User config for token monitoring, persisted in the App Group so the CLI
/// hook + app + future widgets agree. Mirrors `SyncSettings`.
@MainActor
public final class TokenMonitorSettings: ObservableObject {
    public static let shared = TokenMonitorSettings()

    private let defaults: UserDefaults
    private enum Key {
        static let enabled = "doris.tokens.monitoringEnabled"
        static let tools = "doris.tokens.enabledTools"
        static let openAIKey = "doris.tokens.openAIKey"
        static let cursorToken = "doris.tokens.cursorToken"
        static let lastCollectAt = "doris.tokens.lastCollectAt"
        static let claudeCap = "doris.tokens.claudeWindowCap"
    }

    /// Master switch — off disables collection entirely.
    @Published public var monitoringEnabled: Bool { didSet { defaults.set(monitoringEnabled, forKey: Key.enabled) } }
    /// Which tools to collect. Defaults to the two local-log sources.
    @Published public var enabledTools: Set<TokenTool> {
        didSet { defaults.set(enabledTools.map(\.rawValue), forKey: Key.tools) }
    }
    @Published public var openAIKey: String { didSet { defaults.set(openAIKey, forKey: Key.openAIKey) } }
    @Published public var cursorToken: String { didSet { defaults.set(cursorToken, forKey: Key.cursorToken) } }
    @Published public var lastCollectAt: Date? { didSet { defaults.set(lastCollectAt, forKey: Key.lastCollectAt) } }
    /// Claude 5-hour-window token cap for estimating remaining %. 0 = unknown
    /// (show tokens used instead of a %). User-configurable since Anthropic
    /// publishes no exact token cap.
    @Published public var claudeWindowCap: Int { didSet { defaults.set(claudeWindowCap, forKey: Key.claudeCap) } }

    private init() {
        let d = UserDefaults(suiteName: DorisIdentifiers.appGroup) ?? .standard
        self.defaults = d
        self.monitoringEnabled = (d.object(forKey: Key.enabled) as? Bool) ?? true
        if let raw = d.array(forKey: Key.tools) as? [String] {
            self.enabledTools = Set(raw.compactMap(TokenTool.init(rawValue:)))
        } else {
            self.enabledTools = [.claudeCode, .codex]   // default: local-log sources
        }
        self.openAIKey = d.string(forKey: Key.openAIKey) ?? ""
        self.cursorToken = d.string(forKey: Key.cursorToken) ?? ""
        self.lastCollectAt = d.object(forKey: Key.lastCollectAt) as? Date
        self.claudeWindowCap = d.integer(forKey: Key.claudeCap)
    }

    public func isEnabled(_ tool: TokenTool) -> Bool { enabledTools.contains(tool) }

    public func setEnabled(_ tool: TokenTool, _ on: Bool) {
        if on { enabledTools.insert(tool) } else { enabledTools.remove(tool) }
    }
}

#endif
