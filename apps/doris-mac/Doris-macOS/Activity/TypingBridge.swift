import AppKit
import Combine
import DorisCore

/// Doris's side of the typing count: runs "Doris 字数助手" (the embedded,
/// unsandboxed helper that reads other apps' text — see `TypingWire` for
/// why it's separate) and records the word counts it hands over.
///
/// Off until the user turns it on in Settings, since turning it on means
/// a second Accessibility entry to approve.
@MainActor
final class TypingBridge: ObservableObject {
    static let shared = TypingBridge()

    enum State: Equatable {
        case off
        /// On, but the helper isn't running (yet), or can't be found.
        case starting
        case needsAccess
        case counting
    }

    @Published private(set) var state: State = .off

    private static let enabledKey = "doris.typing.enabled"
    private var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }
    private var batchSub: DarwinNotify.Subscription?
    private var timer: Timer?
    private var started = false

    private init() {}

    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/DorisTyping.app")
    }

    func start() {
        guard !started else { return }
        started = true
        batchSub = DarwinNotify.subscribe(TypingWire.batchNotification) {
            MainActor.assumeIsolated { TypingBridge.shared.drain() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { TypingBridge.shared.refresh() }
        }
        // Counts the helper wrote while Doris wasn't running.
        drain()
        if enabled { launchHelper() }
        refresh()
    }

    func enable() {
        enabled = true
        launchHelper()
        refresh()
    }

    func disable() {
        enabled = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: TypingWire.helperBundleID) {
            app.terminate()
        }
        state = .off
    }

    /// Shows the system Accessibility prompt for the helper, the settings
    /// pane where it's switched on, and the helper itself in the Finder —
    /// the prompt doesn't always add it to the list, and dragging it in does.
    func requestAccess() {
        if !helperRunning { launchHelper() }
        DarwinNotify.post(TypingWire.promptNotification)
        NSWorkspace.shared.activateFileViewerSelecting([Self.helperURL])
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when the helper counts what lands in the frontmost app — so
    /// Doris's own dictation there needn't be counted twice.
    var countsFrontmost: Bool {
        guard state == .counting else { return false }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        return !TypingWire.skippedBundles.contains(front)
    }

    // MARK: -

    private var helperRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: TypingWire.helperBundleID).isEmpty
    }

    private func launchHelper() {
        guard !helperRunning else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: config) { _, error in
            if let error { NSLog("[Typing] helper launch failed: \(error)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { TypingBridge.shared.refresh() }
            }
        }
    }

    private func refresh() {
        drain()
        guard enabled else { state = .off; return }
        guard helperRunning else {
            state = .starting
            launchHelper()   // it quit or crashed; bring it back
            return
        }
        state = TypingWire.readStatus()?.trusted == true ? .counting : .needsAccess
    }

    private func drain() {
        guard let recorder = ActivityRecorder.shared else { return }
        TypingWire.drain { batch in
            for e in batch.entries {
                if e.words > 0 { recorder.addWords(e.words, at: e.at) }
                else if e.words < 0 { recorder.removeWords(-e.words, at: e.at) }
            }
        }
    }
}
