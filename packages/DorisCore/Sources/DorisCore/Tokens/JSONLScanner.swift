#if os(macOS)

import Foundation

/// Incremental line reader for append-only JSONL logs. Tracks a per-file
/// byte offset so each launch only parses content appended since last time,
/// and only ever hands back **complete** lines (a half-written trailing line
/// is left for the next pass). The returned offset map is rebuilt from the
/// current file set, so offsets for deleted files are dropped automatically.
enum JSONLScanner {
    static func decodeOffsets(_ json: String?) -> [String: UInt64] {
        guard let json, let d = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: UInt64].self, from: d) else { return [:] }
        return dict
    }

    static func encodeOffsets(_ offsets: [String: UInt64]) -> String {
        (try? JSONEncoder().encode(offsets)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// All `*.jsonl` under `root` (recursive). Empty if root is missing.
    static func jsonlFiles(under root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en where url.pathExtension == "jsonl" { out.append(url) }
        return out
    }

    /// Reads complete lines appended past each file's saved offset, invoking
    /// `onLine(path, lineData)` per line, and returns the advanced offsets.
    static func scanNewLines(files: [URL], offsets: [String: UInt64],
                             onLine: (String, Data) -> Void) -> [String: UInt64] {
        var newOffsets: [String: UInt64] = [:]
        for file in files {
            let path = file.path
            let start = offsets[path] ?? 0
            guard let fh = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? fh.close() }
            var end = start
            do {
                try fh.seek(toOffset: start)
                let data = try fh.readToEnd() ?? Data()
                if let lastNL = data.lastIndex(of: 0x0A) {
                    let completeCount = data.distance(from: data.startIndex, to: data.index(after: lastNL))
                    let complete = data.prefix(completeCount)
                    var lineStart = complete.startIndex
                    for i in complete.indices where complete[i] == 0x0A {
                        if i > lineStart { onLine(path, Data(complete[lineStart..<i])) }
                        lineStart = complete.index(after: i)
                    }
                    end = start + UInt64(completeCount)
                } else {
                    end = start   // nothing complete yet; wait for the newline
                }
            } catch { end = start }
            newOffsets[path] = end
        }
        return newOffsets
    }
}

#endif
