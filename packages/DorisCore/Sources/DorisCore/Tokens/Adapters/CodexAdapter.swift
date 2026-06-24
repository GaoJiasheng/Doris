#if os(macOS)

import Foundation

/// Parses the Codex CLI's session rollouts at
/// `~/.codex/sessions/**/rollout-*.jsonl`. Token usage arrives as
/// `event_msg` lines whose `payload.type == "token_count"`, carrying
/// `payload.info.last_token_usage` (the per-turn delta:
/// input/cached_input/output/reasoning_output). Summing the deltas across a
/// session equals its total. Model id comes from the preceding
/// `session_meta` / `turn_context` line.
public struct CodexAdapter: TokenSourceAdapter {
    public let tool: TokenTool = .codex
    public init() {}

    private var sessionsRoot: URL {
        integrationsRealHome().appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public var watchPaths: [URL] { [sessionsRoot] }

    public func status() -> TokenSourceStatus {
        FileManager.default.fileExists(atPath: sessionsRoot.path) ? .ok : .unavailable
    }

    public func collect(cursorJSON: String?) throws -> (samples: [TokenSample], cursorJSON: String) {
        let offsets = JSONLScanner.decodeOffsets(cursorJSON)
        let files = JSONLScanner.jsonlFiles(under: sessionsRoot)
            .filter { $0.lastPathComponent.hasPrefix("rollout-") }

        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter(); isoPlain.formatOptions = [.withInternetDateTime]

        var samples: [TokenSample] = []
        var modelByPath: [String: String] = [:]

        let newOffsets = JSONLScanner.scanNewLines(files: files, offsets: offsets) { path, data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let type = (obj["type"] as? String) ?? ""
            let payload = obj["payload"] as? [String: Any]

            // Track the active model id from meta/context lines.
            if type == "session_meta" || type == "turn_context" {
                if let m = Self.findString(in: obj, key: "model") { modelByPath[path] = m }
                return
            }
            guard type == "event_msg",
                  let payload, (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any] else { return }

            let inputAll = (last["input_tokens"] as? Int) ?? 0
            let cached = (last["cached_input_tokens"] as? Int) ?? 0
            let output = (last["output_tokens"] as? Int) ?? 0
            let reasoning = (last["reasoning_output_tokens"] as? Int) ?? 0
            // input_tokens includes the cached portion; split so cost maths
            // bill the cached part at the cheaper cache-read rate.
            let uncachedInput = max(0, inputAll - cached)
            guard uncachedInput + cached + output + reasoning > 0 else { return }

            // Stable, content-based dedup key. `total_token_usage.total_tokens`
            // is cumulative + monotonic, so it's unique per non-zero turn and
            // survives incremental re-scans. The OLD key used a per-collect
            // sequence number (`seq`) that reset every collect — so re-scanning
            // a still-growing session produced colliding keys and the new turns
            // were silently dropped as "duplicates" (only the first few turns of
            // long sessions ever got recorded; e.g. a 24M-token session showed
            // ~0.6M). Timestamp tiebreak guards a missing total_token_usage.
            let cumTotal = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int ?? 0
            let file = URL(fileURLWithPath: path).lastPathComponent
            let sessionId = (modelByPath[path] != nil) ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent : ""
            let tsStr = (obj["timestamp"] as? String) ?? ""
            let ts = iso.date(from: tsStr) ?? isoPlain.date(from: tsStr) ?? Date()

            samples.append(TokenSample(
                tool: .codex, model: modelByPath[path] ?? "codex", sessionId: sessionId,
                dedupKey: "codex:\(file)#\(cumTotal):\(tsStr)",
                inputTokens: uncachedInput, outputTokens: output,
                cacheCreateTokens: 0, cacheReadTokens: cached,
                reasoningTokens: reasoning, serviceTier: nil, ts: ts))
        }
        return (samples, JSONLScanner.encodeOffsets(newOffsets))
    }

    /// Depth-first search for the first String value stored under `key`.
    private static func findString(in obj: Any, key: String) -> String? {
        if let dict = obj as? [String: Any] {
            if let v = dict[key] as? String, !v.isEmpty { return v }
            for v in dict.values { if let f = findString(in: v, key: key) { return f } }
        } else if let arr = obj as? [Any] {
            for v in arr { if let f = findString(in: v, key: key) { return f } }
        }
        return nil
    }
}

#endif
