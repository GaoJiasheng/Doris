#if os(macOS)

import Foundation
import SwiftData
import DorisIPC

/// Dedicated **local** (non-CloudKit) SwiftData container for token-usage
/// data. Kept separate from the main `ModelContainerFactory` graph because:
///   • it can hold tens of thousands of raw events — no business syncing
///     that to iOS over CloudKit,
///   • the token UI is macOS-only,
///   • decoupling means a token-schema change can never disturb the synced
///     Notes/Messages graph.
/// Lives next to the main store in the App Group container.
public enum TokenStore {
    public static let schema = Schema([
        TokenUsageEvent.self,
        TokenUsageDaily.self,
        TokenIngestState.self
    ])

    /// Process-wide shared container (lazily built). Returns nil if the
    /// App Group container is unreachable (token monitoring just stays off).
    public static let shared: ModelContainer? = {
        try? make()
    }()

    public static func make() throws -> ModelContainer {
        let url = try storeURL()
        let config = ModelConfiguration(
            "DorisTokens",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func storeURL() throws -> URL {
        let group = try IPCDirectory.containerURL()
        let dir = group.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("TokenUsage.sqlite")
    }
}

#endif
