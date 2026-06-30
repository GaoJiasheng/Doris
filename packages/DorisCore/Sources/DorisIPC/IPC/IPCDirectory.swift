import Foundation

public enum IPCDirectory {
    public enum DirectoryError: Error {
        case appGroupUnavailable
    }

    /// Returns the App Group container URL, or a development fallback when the binary
    /// is not signed/entitled. The fallback honors `$DORIS_IPC_ROOT` for explicit override.
    public static func containerURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["DORIS_IPC_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DorisIdentifiers.appGroup
        ) {
            return url
        }
        // Fallback for unsigned dev builds (Mac only — on iOS, the App Group
        // is always entitled when running on device or simulator, so this
        // path doesn't apply, and `homeDirectoryForCurrentUser` is iOS-banned).
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("doris-dev", isDirectory: true)
        #else
        // On iOS, fall back to the app's caches dir if the App Group is
        // genuinely missing — better to persist somewhere than crash.
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("doris-fallback", isDirectory: true)
        #endif
    }

    public static func ipcRoot() throws -> URL {
        #if os(macOS)
        // IPC inbox/outbox live OUTSIDE the App-Group container so the Claude
        // Code / Codex `doris notify` Stop hooks (run by those CLIs) don't trip
        // macOS's "<app> wants to access other apps' data" prompt on every run
        // (that prompt fires when a process touches another app's container,
        // and macOS won't reliably remember the grant for a CLI). `~/.doris` is
        // a plain dotfile dir, not a protected app container; the sandboxed app
        // reaches it via a home-relative-path entitlement — the same mechanism
        // used for `~/.claude` and `~/.codex`. `$DORIS_IPC_ROOT` still wins.
        if let override = ProcessInfo.processInfo.environment["DORIS_IPC_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("IPC", isDirectory: true)
        }
        return realHome().appendingPathComponent(".doris/ipc", isDirectory: true)
        #else
        return try containerURL().appendingPathComponent("IPC", isDirectory: true)
        #endif
    }

    #if os(macOS)
    /// The user's REAL home (passwd entry), bypassing the App Sandbox container
    /// redirect — so `~/.doris` resolves to the same actual home the unsandboxed
    /// CLI writes to and that the home-relative-path entitlement grants the app.
    private static func realHome() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    #endif

    public static func inboxDir() throws -> URL {
        try ipcRoot().appendingPathComponent("inbox", isDirectory: true)
    }

    public static func outboxDir() throws -> URL {
        try ipcRoot().appendingPathComponent("outbox", isDirectory: true)
    }

    public static func processedDir() throws -> URL {
        try ipcRoot().appendingPathComponent("processed", isDirectory: true)
    }

    public static func attachmentsDir() throws -> URL {
        try containerURL().appendingPathComponent("Attachments", isDirectory: true)
    }

    public static func backupsDir() throws -> URL {
        try containerURL().appendingPathComponent("Backups", isDirectory: true)
    }

    public static func logsDir() throws -> URL {
        try containerURL().appendingPathComponent("Logs", isDirectory: true)
    }

    /// Create ONLY the IPC inbox/outbox/processed dirs (under `ipcRoot()`).
    /// The CLI must use this rather than `ensureDirectories()`: on macOS it
    /// stays inside `~/.doris` and never touches the App-Group container, so
    /// the Claude Code / Codex `doris notify` hooks don't trip macOS's "wants
    /// to access other apps' data" prompt on every run.
    public static func ensureIPCDirectories() throws {
        let fm = FileManager.default
        let ipc = try ipcRoot()
        for sub in ["inbox", "outbox", "processed"] {
            try fm.createDirectory(at: ipc.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    /// Full set: the App-Group container data dirs (Attachments/Backups/Logs)
    /// plus the IPC dirs. The APP calls this; the CLI uses
    /// `ensureIPCDirectories()` instead (it must not touch the container).
    @discardableResult
    public static func ensureDirectories() throws -> URL {
        let fm = FileManager.default
        let root = try containerURL()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for sub in ["Attachments", "Backups", "Logs"] {
            try fm.createDirectory(at: root.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        try ensureIPCDirectories()
        return root
    }

    public static func newRequestFilename(for id: UUID) -> String {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        return "\(ms)-\(id.uuidString).json"
    }
}
