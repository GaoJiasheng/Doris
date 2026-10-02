import Foundation

public enum IPCWriter {
    public enum WriteError: Error {
        case directoryUnavailable
        case keychainUnavailable(Error)
        case encodingFailed(Error)
        case writeFailed(Error)
    }

    /// Write a request to the inbox queue, signed with the shared HMAC secret if available.
    /// Returns the URL of the file we wrote.
    @discardableResult
    public static func enqueue(_ request: IPCRequest) throws -> URL {
        let inbox: URL
        do {
            inbox = try IPCDirectory.inboxDir()
        } catch {
            throw WriteError.directoryUnavailable
        }
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        var signed = request
        if let secret = try? KeychainSecretStore.loadSecret() {
            signed = (try? DorisHMAC.sign(request, with: secret)) ?? request
        }
        let data: Data
        do {
            data = try IPCEncoding.encoder.encode(signed)
        } catch {
            throw WriteError.encodingFailed(error)
        }

        let filename = IPCDirectory.newRequestFilename(for: signed.id)
        let target = inbox.appendingPathComponent(filename)
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            throw WriteError.writeFailed(error)
        }
        return target
    }

    /// Post the Darwin notification that wakes the running app.
    public static func kick() {
        DarwinNotify.post(DorisIdentifiers.darwinKickName)
    }
}

/// Answers to requests that expect one. The app writes a response file
/// named after the request id; the CLI waiting on it reads and removes it.
public enum IPCResponseStore {
    public static func write(_ response: IPCResponse) throws {
        let dir = try IPCDirectory.responsesDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try IPCEncoding.encoder.encode(response)
        // Atomic, so the reader never sees half a file.
        try data.write(to: try IPCDirectory.responseURL(for: response.requestID), options: .atomic)
    }

    /// The response for `id` if it has arrived — consumed, so it's read once.
    public static func take(_ id: UUID) -> IPCResponse? {
        guard let url = try? IPCDirectory.responseURL(for: id),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? IPCEncoding.decoder.decode(IPCResponse.self, from: data)
    }

    /// Responses nobody collected (the CLI gave up waiting) — cleared after
    /// a while so the directory doesn't grow.
    public static func pruneStale(olderThan age: TimeInterval = 600, now: Date = Date()) {
        guard let dir = try? IPCDirectory.responsesDir(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > age {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
