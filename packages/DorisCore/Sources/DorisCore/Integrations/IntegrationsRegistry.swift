#if os(macOS)

import Foundation
import Combine

/// Default integrations shipped with the product. Top-level (not
/// nested under the @MainActor registry) so the SwiftUI default-
/// parameter call site can reach it without crossing an actor
/// boundary. Order matters — this is the order rows appear in
/// Settings. Most-supported (.full) entries first so the "good case"
/// is what the user sees first; .manual entries follow.
public let dorisDefaultIntegrationProviders: [any IntegrationProvider] = [
    ClaudeCodeIntegration(),
    CodexIntegration(),
    ChatGPTIntegration()
]

/// Single source of truth for the Settings "应用集成" section. Holds
/// the static provider list + an observable cache of each provider's
/// last-known status, so the UI can render without doing filesystem
/// I/O on every redraw. Refreshing is explicit (called on appear,
/// and after every register/unregister) so we don't pay for the disk
/// reads every SwiftUI tick.
@MainActor
public final class IntegrationsRegistry: ObservableObject {
    public static let shared = IntegrationsRegistry()

    public let providers: [any IntegrationProvider]

    /// Status keyed by provider.id. Defaults to `.notApplicable` until
    /// the first `refresh()` lands real values — that way the UI can
    /// render placeholders immediately without flashing "not registered".
    @Published public private(set) var statuses: [String: IntegrationStatus] = [:]

    /// True while a refresh is in flight. Lets the UI dim or show a
    /// spinner on the section.
    @Published public private(set) var isRefreshing: Bool = false

    private init(providers: [any IntegrationProvider] = dorisDefaultIntegrationProviders) {
        self.providers = providers
        // Seed: providers with .notApplicable supportTier should stay
        // .notApplicable; full/manual providers stay unknown until refresh.
        for p in providers {
            statuses[p.id] = .notApplicable
        }
    }

    /// Re-poll every provider in parallel and publish the new statuses
    /// in a single batch update. Called on Settings panel appear and
    /// after every successful register/unregister.
    public func refresh() async {
        isRefreshing = true
        // Run all `currentStatus()` calls concurrently — each does a
        // tiny filesystem read; parallelism is essentially free and
        // keeps the panel snappy if any one provider stalls.
        let pairs: [(String, IntegrationStatus)] = await withTaskGroup(of: (String, IntegrationStatus).self) { group in
            for provider in providers {
                group.addTask { (provider.id, await provider.currentStatus()) }
            }
            var collected: [(String, IntegrationStatus)] = []
            for await pair in group {
                collected.append(pair)
            }
            return collected
        }
        for (id, status) in pairs {
            statuses[id] = status
        }
        isRefreshing = false
    }

    /// Register the given provider, then refresh so the row flips
    /// from "未注册" to "已注册" without a panel reopen.
    public func register(_ provider: any IntegrationProvider) async throws {
        try await provider.register()
        await refresh()
    }

    /// Mirror of `register` — same refresh-on-success pattern so the
    /// UI updates immediately.
    public func unregister(_ provider: any IntegrationProvider) async throws {
        try await provider.unregister()
        await refresh()
    }
}

#endif // os(macOS)
