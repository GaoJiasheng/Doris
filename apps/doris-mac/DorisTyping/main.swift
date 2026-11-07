import AppKit
import ApplicationServices
import DorisIPC

/// Doris 字数助手 — the word counter behind Doris's typing stats.
///
/// It lives inside Doris.app and exists only because the App Sandbox
/// keeps Doris itself from reading other apps' text through
/// Accessibility. Doris launches it; it quits when Doris does. It has no
/// UI, keeps no text, and hands Doris word counts through
/// `TypingWire` files.
@MainActor
final class Helper {
    static let shared = Helper()

    private var pending: [TypingWire.Entry] = []
    private var lastStatus: Bool?
    private var promptSub: DarwinNotify.Subscription?
    private var timers: [Timer] = []

    func start() {
        // Doris launched us; without it there's no one to count for.
        guard Self.dorisRunning() else { exit(0) }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.dorisBundleID else { return }
            MainActor.assumeIsolated { Helper.shared.quit() }
        }

        if !AXIsProcessTrusted() { prompt() }
        promptSub = DarwinNotify.subscribe(TypingWire.promptNotification) {
            MainActor.assumeIsolated { Helper.shared.prompt() }
        }

        TypingCounter.shared.onWords = { n, at in Helper.shared.pending.append(.init(at: at, words: n)) }
        TypingCounter.shared.start()

        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { Helper.shared.tick() }
        })
        tick()
    }

    private func prompt() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func tick() {
        flush()
        let trusted = AXIsProcessTrusted()
        if trusted != lastStatus {
            lastStatus = trusted
            try? TypingWire.write(TypingWire.Status(trusted: trusted, pid: getpid(), updated: Date()))
        }
        if !Self.dorisRunning() { quit() }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        do {
            try TypingWire.write(TypingWire.Batch(entries: pending))
            pending.removeAll()
        } catch {
            NSLog("[DorisTyping] write failed: \(error)")
        }
    }

    private func quit() {
        flush()
        try? TypingWire.write(TypingWire.Status(trusted: AXIsProcessTrusted(), pid: 0, updated: Date()))
        exit(0)
    }

    static let dorisBundleID = "com.gavin.doris"

    static func dorisRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: dorisBundleID).isEmpty
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { Helper.shared.start() }
app.run()
