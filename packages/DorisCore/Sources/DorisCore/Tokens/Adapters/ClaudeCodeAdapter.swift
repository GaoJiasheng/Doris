#if os(macOS)

import Foundation

/// Parses Claude Code's per-session transcripts. Each `type=="assistant"`
/// line carries `message.usage` (input/output/cache_creation/cache_read) +
/// `message.model` + top-level `timestamp` + `requestId` + `message.id`.
///
/// Mirrors ccusage's data model:
///  • Reads every `projects/**/*.jsonl` under each Claude config dir —
///    `~/.claude` AND the newer `~/.config/claude` (+ `$CLAUDE_CONFIG_DIR`).
///  • De-duplicates on the `message.id` + `requestId` COMPOSITE. Resumed
///    sessions copy earlier messages into the new file, so the same pair can
///    appear in multiple files; the composite (not requestId alone) counts
///    each model response exactly once.
///  • Claude Code's JSONL has no pre-computed cost field, so cost is computed
///    from token counts downstream (TokenPricing) — ccusage's "calculate" mode.
public struct ClaudeCodeAdapter: TokenSourceAdapter {
    public let tool: TokenTool = .claudeCode
    public init() {}

    /// Every place Claude Code may keep `projects/`. Order doesn't matter —
    /// files are keyed by absolute path and de-duplicated by content key.
    private var projectsRoots: [URL] {
        let home = integrationsRealHome()
        var roots: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            for dir in env.split(separator: ",") {
                let base = String(dir).trimmingCharacters(in: .whitespaces)
                if !base.isEmpty {
                    roots.append(URL(fileURLWithPath: base, isDirectory: true)
                        .appendingPathComponent("projects", isDirectory: true))
                }
            }
        }
        roots.append(home.appendingPathComponent(".config/claude/projects", isDirectory: true))
        roots.append(home.appendingPathComponent(".claude/projects", isDirectory: true))
        return roots
    }

    public var watchPaths: [URL] { projectsRoots }

    public func status() -> TokenSourceStatus {
        let exists = projectsRoots.contains { FileManager.default.fileExists(atPath: $0.path) }
        return exists ? .ok : .unavailable
    }

    public func collect(cursorJSON: String?) throws -> (samples: [TokenSample], cursorJSON: String) {
        let offsets = JSONLScanner.decodeOffsets(cursorJSON)
        let files = projectsRoots.flatMap { JSONLScanner.jsonlFiles(under: $0) }

        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter(); isoPlain.formatOptions = [.withInternetDateTime]

        var samples: [TokenSample] = []
        let newOffsets = JSONLScanner.scanNewLines(files: files, offsets: offsets) { _, data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any] else { return }
            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            guard input + output + cacheCreate + cacheRead > 0 else { return }

            let model = (msg["model"] as? String) ?? "unknown"
            let sessionId = (obj["sessionId"] as? String) ?? ""
            // Composite dedup key (ccusage-style). Falls back to a unique id
            // only when BOTH are missing, so such lines are never merged away.
            let mid = (msg["id"] as? String) ?? ""
            let rid = (obj["requestId"] as? String) ?? ""
            let dedupKey = (mid.isEmpty && rid.isEmpty) ? "cc:\(UUID().uuidString)" : "cc:\(mid)|\(rid)"
            let tsStr = (obj["timestamp"] as? String) ?? ""
            let ts = iso.date(from: tsStr) ?? isoPlain.date(from: tsStr) ?? Date()

            samples.append(TokenSample(
                tool: .claudeCode, model: model, sessionId: sessionId,
                dedupKey: dedupKey,
                inputTokens: input, outputTokens: output,
                cacheCreateTokens: cacheCreate, cacheReadTokens: cacheRead,
                reasoningTokens: 0, serviceTier: usage["service_tier"] as? String, ts: ts))
        }
        return (samples, JSONLScanner.encodeOffsets(newOffsets))
    }
}

#endif
