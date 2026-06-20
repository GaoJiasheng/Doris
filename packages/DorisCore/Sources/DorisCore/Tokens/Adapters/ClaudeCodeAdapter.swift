#if os(macOS)

import Foundation

/// Parses Claude Code's per-session transcripts at
/// `~/.claude/projects/**/*.jsonl`. Each `type=="assistant"` line carries
/// `message.usage` (input/output/cache_creation/cache_read) + `message.model`
/// + top-level `timestamp` + `requestId`. Resumed sessions copy earlier
/// messages into the new file, so the same `requestId` can appear twice —
/// `dedupKey` lets the collector count it once.
public struct ClaudeCodeAdapter: TokenSourceAdapter {
    public let tool: TokenTool = .claudeCode
    public init() {}

    private var projectsRoot: URL {
        integrationsRealHome().appendingPathComponent(".claude/projects", isDirectory: true)
    }

    public var watchPaths: [URL] { [projectsRoot] }

    public func status() -> TokenSourceStatus {
        FileManager.default.fileExists(atPath: projectsRoot.path) ? .ok : .unavailable
    }

    public func collect(cursorJSON: String?) throws -> (samples: [TokenSample], cursorJSON: String) {
        let offsets = JSONLScanner.decodeOffsets(cursorJSON)
        let files = JSONLScanner.jsonlFiles(under: projectsRoot)

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
            let reqId = (obj["requestId"] as? String) ?? (msg["id"] as? String) ?? UUID().uuidString
            let tsStr = (obj["timestamp"] as? String) ?? ""
            let ts = iso.date(from: tsStr) ?? isoPlain.date(from: tsStr) ?? Date()

            samples.append(TokenSample(
                tool: .claudeCode, model: model, sessionId: sessionId,
                dedupKey: "cc:\(reqId)",
                inputTokens: input, outputTokens: output,
                cacheCreateTokens: cacheCreate, cacheReadTokens: cacheRead,
                reasoningTokens: 0, serviceTier: usage["service_tier"] as? String, ts: ts))
        }
        return (samples, JSONLScanner.encodeOffsets(newOffsets))
    }
}

#endif
