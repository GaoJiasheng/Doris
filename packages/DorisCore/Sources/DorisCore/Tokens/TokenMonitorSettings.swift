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
        /// Every tool this install has already been offered. Lets a tool added
        /// in a later version switch itself on once — see `init`.
        static let seenTools = "doris.tokens.seenTools"
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

    private init() {
        let d = UserDefaults(suiteName: DorisIdentifiers.appGroup) ?? .standard
        self.defaults = d
        self.monitoringEnabled = (d.object(forKey: Key.enabled) as? Bool) ?? true
        // Tools whose usage sits in local logs and needs no key/config: safe to
        // have on by default.
        let zeroConfig = Set(TokenTool.allCases.filter(\.readsLocalLogsOnly))
        if let raw = d.array(forKey: Key.tools) as? [String] {
            var tools = Set(raw.compactMap(TokenTool.init(rawValue:)))
            // A tool added in a later version isn't in this install's saved set,
            // so it would stay invisible forever — the user adds the adapter,
            // sees nothing, and gets no hint why. Switch on zero-config tools
            // the first time this install ever sees them. Tools already offered
            // are recorded, so a deliberate opt-out is never re-enabled.
            let seen = Set((d.array(forKey: Key.seenTools) as? [String] ?? [])
                .compactMap(TokenTool.init(rawValue:)))
            let neverOffered = zeroConfig.subtracting(seen).subtracting(tools)
            if !neverOffered.isEmpty {
                tools.formUnion(neverOffered)
                d.set(tools.map(\.rawValue), forKey: Key.tools)
            }
            self.enabledTools = tools
        } else {
            self.enabledTools = zeroConfig
        }
        // Record the full roster so today's new tools count as "offered" next
        // launch, whether or not they were switched on above.
        d.set(TokenTool.allCases.map(\.rawValue), forKey: Key.seenTools)
        self.openAIKey = d.string(forKey: Key.openAIKey) ?? ""
        self.cursorToken = d.string(forKey: Key.cursorToken) ?? ""
        self.lastCollectAt = d.object(forKey: Key.lastCollectAt) as? Date
    }

    public func isEnabled(_ tool: TokenTool) -> Bool { enabledTools.contains(tool) }

    public func setEnabled(_ tool: TokenTool, _ on: Bool) {
        if on { enabledTools.insert(tool) } else { enabledTools.remove(tool) }
    }
}

#endif
