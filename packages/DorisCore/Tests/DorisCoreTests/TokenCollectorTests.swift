#if os(macOS)
import XCTest
import SwiftData
@testable import DorisCore

final class TokenCollectorTests: XCTestCase {
    private func sample(_ key: String) -> TokenSample {
        TokenSample(tool: .codex, model: "m", sessionId: "s", dedupKey: key, inputTokens: 1, outputTokens: 1, ts: Date())
    }

    private func store(_ key: String, in ctx: ModelContext) {
        ctx.insert(TokenUsageEvent(dedupKey: key, toolRaw: "codex", model: "m", sessionId: "s",
                                   inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0,
                                   reasoningTokens: 0, serviceTier: nil, costUSD: 0, ts: Date()))
    }

    func testStoredKeysAcrossLookupBatches() throws {
        let config = ModelConfiguration(schema: TokenStore.schema, isStoredInMemoryOnly: true)
        let ctx = ModelContext(try ModelContainer(for: TokenStore.schema, configurations: [config]))
        // More than one 500-key lookup, stored keys at both ends.
        let keys = (0..<1_200).map { "k\($0)" }
        for key in keys where Int(key.dropFirst())! % 3 == 0 { store(key, in: ctx) }
        try ctx.save()

        let found = try TokenCollector.storedKeys(among: keys.map(sample), ctx: ctx)

        XCTAssertEqual(found, Set(keys.filter { Int($0.dropFirst())! % 3 == 0 }))
    }

    func testStoredKeysWithNoSamples() throws {
        let config = ModelConfiguration(schema: TokenStore.schema, isStoredInMemoryOnly: true)
        let ctx = ModelContext(try ModelContainer(for: TokenStore.schema, configurations: [config]))
        XCTAssertTrue(try TokenCollector.storedKeys(among: [], ctx: ctx).isEmpty)
    }
}
#endif
