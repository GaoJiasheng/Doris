import Foundation

/// How the typing helper hands word counts to Doris.
///
/// macOS's App Sandbox blocks reading other apps' text through
/// Accessibility, so the counting runs in a small unsandboxed helper app
/// embedded in Doris ("Doris 字数助手"). It sends Doris numbers only — never
/// text — as small JSON files in `~/.doris/ipc/typing/`:
///
/// - `words-*.json`: a `Batch` of signed word deltas. Each file is written
///   once (temp file + rename) and deleted by Doris after it's applied, so
///   every delta is counted exactly once.
/// - `status.json`: whether the helper has Accessibility access, so
///   Settings can say so.
///
/// A Darwin notification nudges Doris when a batch lands.
public enum TypingWire {
    public static let helperBundleID = "com.gavin.doris.typing"
    public static let batchNotification = "com.gavin.doris.typing.batch"
    /// Doris → helper: ask for the Accessibility prompt again.
    public static let promptNotification = "com.gavin.doris.typing.prompt"

    /// Apps whose accessible text isn't what the user typed (terminals:
    /// their text includes program output). The helper skips them; Doris's
    /// own dictation into them is counted by Doris instead.
    public static let skippedBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
    ]

    public struct Entry: Codable, Equatable, Sendable {
        public var at: Date
        /// Words produced (positive) or given back after a quick fix (negative).
        public var words: Int
        public init(at: Date, words: Int) { self.at = at; self.words = words }
    }

    public struct Batch: Codable, Sendable {
        public var entries: [Entry]
        public init(entries: [Entry]) { self.entries = entries }
    }

    public struct Status: Codable, Sendable {
        public var trusted: Bool
        public var pid: Int32
        public var updated: Date
        public init(trusted: Bool, pid: Int32, updated: Date) {
            self.trusted = trusted; self.pid = pid; self.updated = updated
        }
    }

    public static func directory() throws -> URL {
        try IPCDirectory.ipcRoot().appendingPathComponent("typing", isDirectory: true)
    }

    public static func statusURL() throws -> URL {
        try directory().appendingPathComponent("status.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }()

    // MARK: Helper side

    public static func write(_ batch: Batch) throws {
        guard !batch.entries.isEmpty else { return }
        let dir = try directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "words-\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
        let tmp = dir.appendingPathComponent(".\(name).tmp")
        try encoder.encode(batch).write(to: tmp)
        try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(name))
        DarwinNotify.post(batchNotification)
    }

    public static func write(_ status: Status) throws {
        let dir = try directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(status).write(to: try statusURL(), options: .atomic)
    }

    // MARK: Doris side

    /// Hands each pending batch to `apply`, oldest first, deleting it
    /// afterwards. A file that won't decode is deleted too.
    public static func drain(_ apply: (Batch) -> Void) {
        guard let dir = try? directory(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names.sorted() where name.hasPrefix("words-") && name.hasSuffix(".json") {
            let url = dir.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), let batch = try? decoder.decode(Batch.self, from: data) {
                apply(batch)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public static func readStatus() -> Status? {
        guard let url = try? statusURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Status.self, from: data)
    }
}
