#if os(macOS)

import Foundation

/// Parses LM Studio's chat history at
/// `~/.lmstudio/conversations/*.conversation.json`.
///
/// Each assistant turn stores its generation stats at
/// `messages[].versions[].steps[].genInfo.stats`:
///
///     { "promptTokensCount": 25, "predictedTokensCount": 1205,
///       "totalTokensCount": 1230, "tokensPerSecond": 89.9, ... }
///
/// with the model at `genInfo.identifier` (e.g. `qwen3.5-35b-a3b@8bit`).
///
/// **Timestamps.** The JSON carries no per-message date — only
/// conversation-level `createdAt` / `assistantLastMessagedAt`. But each step's
/// `stepIdentifier` is `<epochMillis>-<random>`, so the millisecond prefix
/// dates each individual generation. That matters: attributing a whole
/// conversation to one date would smear a chat that spans days across the
/// wrong ones. We fall back to the conversation timestamp only if the prefix
/// won't parse.
///
/// **Two sources, no overlap.** GUI chats live in `conversations/`; anything
/// that goes through the OpenAI-compatible local server (your own code, the
/// `lms` CLI, an agent pointed at `localhost:1234`, …) is picked up from
/// `server-logs/`, where each answered request is logged as
/// `Generated prediction: { … "usage": {...} }`. The two can't double-count:
/// GUI chats don't travel over the HTTP server (it's opt-in and off by
/// default, yet the GUI still records conversations).
///
/// The server side needs LM Studio's **`fileLoggingMode` set to `full`** —
/// on the default `succinct` the response bodies (and therefore the usage
/// numbers) are never written. `status()` reports that rather than silently
/// counting nothing.
///
/// **Cost is always 0.** These are local models; `TokenPricing.rate` has no
/// entry for them and returns nil → cost 0. That's correct rather than
/// missing data: the tokens are free, and they're worth counting for volume.
public struct LMStudioAdapter: TokenSourceAdapter {
    public let tool: TokenTool = .lmStudio
    public init() {}

    private var lmRoot: URL {
        integrationsRealHome().appendingPathComponent(".lmstudio", isDirectory: true)
    }
    private var conversationsRoot: URL { lmRoot.appendingPathComponent("conversations", isDirectory: true) }
    private var serverLogsRoot: URL { lmRoot.appendingPathComponent("server-logs", isDirectory: true) }
    private var serverConfig: URL {
        lmRoot.appendingPathComponent(".internal/http-server-config.json")
    }

    public var watchPaths: [URL] { [conversationsRoot, serverLogsRoot] }

    public func status() -> TokenSourceStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: lmRoot.path) else { return .unavailable }

        // Local-server usage is only recoverable when LM Studio writes full
        // response bodies. Say so — otherwise API/CLI traffic just silently
        // wouldn't be counted and the totals would look wrong for no visible
        // reason.
        if fileLoggingMode() != "full" {
            return .needsConfig(NSLocalizedString(
                "Counting LM Studio chats. To also count local-server usage (your own code / the lms CLI), set Developer → Server → File Logging Mode to \"full\" in LM Studio.",
                comment: ""))
        }
        guard fm.fileExists(atPath: conversationsRoot.path)
                || fm.fileExists(atPath: serverLogsRoot.path) else {
            return .needsConfig(NSLocalizedString(
                "No LM Studio activity yet — token usage appears after your first request.",
                comment: ""))
        }
        return .ok
    }

    /// `off` | `succinct` | `full`, per LM Studio's own server settings.
    private func fileLoggingMode() -> String {
        guard let data = try? Data(contentsOf: serverConfig),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mode = obj["fileLoggingMode"] as? String
        else { return "succinct" }   // LM Studio's own default
        return mode
    }

    /// Cursor for both sources: conversation files keyed by path → mtime,
    /// server logs keyed by path → byte offset already consumed.
    private struct Cursor: Codable {
        var conversationMTimes: [String: Double] = [:]
        var serverLogOffsets: [String: UInt64] = [:]
    }

    public func collect(cursorJSON: String?) throws -> (samples: [TokenSample], cursorJSON: String) {
        var cursor = Cursor()
        if let cursorJSON, let data = cursorJSON.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode(Cursor.self, from: data) {
                cursor = decoded
            } else if let legacy = try? JSONDecoder().decode([String: Double].self, from: data) {
                // Cursor from the conversations-only version of this adapter.
                cursor.conversationMTimes = legacy
            }
        }

        var samples = collectConversations(&cursor)
        samples.append(contentsOf: collectServerLogs(&cursor))

        let encoded = (try? JSONEncoder().encode(cursor))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return (samples, encoded)
    }

    // MARK: - Local server (API / CLI / anything on :1234)

    /// Scans `server-logs/**/*.log` for `Generated prediction: { … }` blocks.
    /// Each is a complete OpenAI-shaped response, so `id` gives a stable dedup
    /// key, `created` the timestamp, and `usage` the counts — no guessing.
    private func collectServerLogs(_ cursor: inout Cursor) -> [TokenSample] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: serverLogsRoot,
                                         includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var samples: [TokenSample] = []

        for case let url as URL in walker where url.pathExtension == "log" {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }

            let start = cursor.serverLogOffsets[url.path] ?? 0
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            // Log rotated/truncated under us → re-read from the top.
            let from: UInt64 = (size ?? 0) < start ? 0 : start
            guard (size ?? 0) > from else { continue }

            try? handle.seek(toOffset: from)
            guard let data = try? handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { continue }

            var lastParsedEnd: String.Index = text.startIndex
            for (blockRange, json) in Self.predictionBlocks(in: text) {
                if let sample = Self.sample(fromPrediction: json) { samples.append(sample) }
                lastParsedEnd = blockRange.upperBound
            }

            // Advance to EOF, except when a prediction is still being written —
            // then stop at that marker so the partial block is re-read next
            // pass instead of being lost.
            //
            // Advancing on a chunk with NO complete block matters as much as
            // the parsed case: most of these logs (some 10 MB apiece) contain
            // no predictions at all, and leaving their offset at 0 meant
            // re-reading ~70 MB on every collection tick, forever.
            let dangling = text.range(of: "Generated prediction: ",
                                      options: .backwards,
                                      range: lastParsedEnd..<text.endIndex)
            let consumeUpTo = dangling?.lowerBound ?? text.endIndex
            cursor.serverLogOffsets[url.path] = from + UInt64(text[..<consumeUpTo].utf8.count)
        }
        return samples
    }

    /// Extracts every complete `Generated prediction: {...}` JSON object.
    /// The log pretty-prints them across many lines, so we brace-match rather
    /// than parse line-wise; an unbalanced trailing block (still being
    /// written) is skipped.
    static func predictionBlocks(in text: String) -> [(Range<String.Index>, [String: Any])] {
        let marker = "Generated prediction: "
        var out: [(Range<String.Index>, [String: Any])] = []
        var search = text.startIndex

        while let hit = text.range(of: marker, range: search..<text.endIndex) {
            guard let open = text[hit.upperBound...].firstIndex(of: "{") else { break }
            var depth = 0
            var inString = false
            var escaped = false
            var end: String.Index?

            var i = open
            while i < text.endIndex {
                let c = text[i]
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString.toggle() }
                else if !inString {
                    if c == "{" { depth += 1 }
                    else if c == "}" {
                        depth -= 1
                        if depth == 0 { end = text.index(after: i); break }
                    }
                }
                i = text.index(after: i)
            }
            guard let end else { break }   // truncated tail — leave for next pass

            if let data = String(text[open..<end]).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                out.append((open..<end, obj))
            }
            search = end
        }
        return out
    }

    private static func sample(fromPrediction obj: [String: Any]) -> TokenSample? {
        guard let usage = obj["usage"] as? [String: Any] else { return nil }
        let input = (usage["prompt_tokens"] as? Int) ?? 0
        let output = (usage["completion_tokens"] as? Int) ?? 0
        guard input + output > 0 else { return nil }
        let reasoning = (usage["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? Int ?? 0

        let id = (obj["id"] as? String) ?? UUID().uuidString
        let model = (obj["model"] as? String) ?? "lm-studio"
        let created = (obj["created"] as? Double) ?? (obj["created"] as? Int).map(Double.init)

        return TokenSample(
            tool: .lmStudio,
            model: model,
            sessionId: "server",
            dedupKey: "lmstudio:api:\(id)",
            inputTokens: input,
            // `completion_tokens` already includes reasoning; keep the split
            // out of `output` so the two columns don't double-count.
            outputTokens: max(0, output - reasoning),
            cacheCreateTokens: 0,
            cacheReadTokens: 0,
            reasoningTokens: reasoning,
            serviceTier: nil,
            ts: created.map { Date(timeIntervalSince1970: $0) } ?? Date()
        )
    }

    // MARK: - GUI chats

    private func collectConversations(_ cursor: inout Cursor) -> [TokenSample] {
        let fm = FileManager.default
        // Conversation files are rewritten in place as a chat grows (unlike the
        // append-only logs the other adapters read), so byte offsets are
        // meaningless — track mtime and re-read a whole file when it changes.
        // Re-reading is safe: every sample carries a stable dedupKey and
        // TokenCollector drops keys it has already stored.
        guard let entries = try? fm.contentsOfDirectory(
            at: conversationsRoot, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        var samples: [TokenSample] = []

        for url in entries where url.lastPathComponent.hasSuffix(".conversation.json") {
            let mtime = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970) ?? 0
            let previous = cursor.conversationMTimes[url.path]
            cursor.conversationMTimes[url.path] = mtime
            if let previous, previous >= mtime { continue }   // unchanged

            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // `<millis>.conversation.json` — the stem is LM Studio's own id.
            let convId = url.lastPathComponent
                .replacingOccurrences(of: ".conversation.json", with: "")
            let fallbackTS = Self.date(fromMillis: root["assistantLastMessagedAt"])
                ?? Self.date(fromMillis: root["createdAt"])
                ?? Date()

            for message in (root["messages"] as? [[String: Any]]) ?? [] {
                for version in (message["versions"] as? [[String: Any]]) ?? [] {
                    for step in (version["steps"] as? [[String: Any]]) ?? [] {
                        guard let genInfo = step["genInfo"] as? [String: Any],
                              let stats = genInfo["stats"] as? [String: Any] else { continue }

                        let input = (stats["promptTokensCount"] as? Int) ?? 0
                        let output = (stats["predictedTokensCount"] as? Int) ?? 0
                        guard input + output > 0 else { continue }

                        let stepId = (step["stepIdentifier"] as? String) ?? ""
                        let model = (genInfo["identifier"] as? String)
                            ?? (genInfo["indexedModelIdentifier"] as? String)
                            ?? "lm-studio"

                        samples.append(TokenSample(
                            tool: .lmStudio,
                            model: model,
                            sessionId: convId,
                            dedupKey: "lmstudio:\(convId)#\(stepId)",
                            inputTokens: input,
                            outputTokens: output,
                            cacheCreateTokens: 0,
                            cacheReadTokens: 0,
                            reasoningTokens: 0,
                            serviceTier: nil,
                            ts: Self.date(fromStepIdentifier: stepId) ?? fallbackTS
                        ))
                    }
                }
            }
        }

        return samples
    }

    // MARK: - Timestamps

    /// `stepIdentifier` is `<epochMillis>-<random>`; the prefix dates the
    /// individual generation. Returns nil if it isn't in that shape so the
    /// caller can fall back to the conversation's own timestamp.
    static func date(fromStepIdentifier id: String) -> Date? {
        guard let prefix = id.split(separator: "-").first,
              let millis = Double(prefix),
              millis > 1_000_000_000_000,          // sane epoch-ms floor (2001+)
              millis < 4_000_000_000_000           // ...and ceiling (2096)
        else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static func date(fromMillis value: Any?) -> Date? {
        guard let millis = (value as? Double) ?? (value as? Int).map(Double.init),
              millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}

#endif
