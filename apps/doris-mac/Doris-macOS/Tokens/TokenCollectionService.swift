import Foundation
import CoreServices
import DorisCore

/// Drives token collection on macOS: watches each adapter's log directory
/// via FSEvents (near-real-time — fires as the JSONL is appended), with a
/// debounce + a periodic safety-net timer, and runs `TokenCollector` off the
/// main actor. The first run backfills history.
@MainActor
final class TokenCollectionService {
    static let shared = TokenCollectionService()

    private var stream: FSEventStreamRef?
    private let fsQueue = DispatchQueue(label: "com.gavin.doris.tokens.fsevents")
    private var debounce: DispatchWorkItem?
    private var timer: Timer?
    private var collector: TokenCollector?
    private var running = false
    private var isCollecting = false

    private init() {}

    func start() {
        guard !running, let container = TokenStore.shared else { return }
        running = true
        collector = TokenCollector(container: container)

        // Initial backfill / catch-up.
        scheduleCollect(delay: 1.0)

        // Watch the existing log dirs of available adapters.
        let paths = TokenSourceRegistry.adapters
            .flatMap { $0.watchPaths }
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
        if !paths.isEmpty { startWatching(paths) }

        // Safety net for API sources / missed events.
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleCollect() }
        }
    }

    /// Manual rescan (Settings "立即扫描" button, app-active, IPC kick).
    func triggerNow() { scheduleCollect(delay: 0) }

    private func scheduleCollect(delay: TimeInterval = 1.5) {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runCollect() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runCollect() {
        guard !isCollecting, let collector,
              TokenMonitorSettings.shared.monitoringEnabled else { return }
        isCollecting = true
        let tools = TokenMonitorSettings.shared.enabledTools
        Task.detached(priority: .utility) {
            _ = collector.collect(tools: tools)
            await MainActor.run {
                TokenMonitorSettings.shared.lastCollectAt = Date()
                self.isCollecting = false
            }
        }
    }

    // MARK: - FSEvents

    private func startWatching(_ paths: [String]) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<TokenCollectionService>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { me.scheduleCollect() }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,   // coalesce bursts of JSONL appends
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, fsQueue)
        FSEventStreamStart(stream)
        self.stream = stream
    }
}
