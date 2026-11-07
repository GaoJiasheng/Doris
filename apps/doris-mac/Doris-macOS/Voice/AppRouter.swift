import AppKit
import ApplicationServices
import Foundation
import DorisIPC
import DorisCore

/// Routes a transcribed string to one of the supported providers:
///
/// - **ChatGPT** / **Claude**: activates the desktop app (cold-launching if
///   needed), pastes the text via ⌘V, optionally presses Return.
/// - **Frontmost**: doesn't change focus — pastes into whatever's currently
///   focused. Useful for Cursor / Slack / a terminal / a code editor.
///
/// All synthetic key events go through `CGEvent` posted to
/// `cghidEventTap`, which requires Accessibility permission. We probe for
/// that up front and surface a clear error if it's missing.
@MainActor
final class AppRouter {
    enum RouterError: LocalizedError {
        case accessibilityNotGranted

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Doris needs Accessibility permission to paste. Enable it in System Settings › Privacy & Security › Accessibility."
            }
        }
    }

    func send(text: String, to provider: VoiceSettings.Provider, autoSubmit: Bool) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard ensureAccessibility(promptUser: true) else {
            DorisLog.voice.error("Accessibility not granted; aborting paste")
            throw RouterError.accessibilityNotGranted
        }

        if let bundleId = provider.bundleId {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                DorisLog.voice.info("activating \(bundleId, privacy: .public) at \(appURL.path, privacy: .public)")
                try await activate(appURL: appURL, bundleId: bundleId)
                for attempt in 0..<10 {
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    if front == bundleId {
                        DorisLog.voice.info("frontmost confirmed (#\(attempt, privacy: .public))")
                        break
                    }
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                paste(trimmed)
                if autoSubmit {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    pressReturn()
                }
            } else if let webURL = provider.webFallback {
                DorisLog.voice.notice("\(bundleId, privacy: .public) not installed — opening web fallback")
                var c = URLComponents(url: webURL, resolvingAgainstBaseURL: false)!
                c.queryItems = [URLQueryItem(name: "q", value: trimmed)]
                if let url = c.url { NSWorkspace.shared.open(url) }
            }
        } else {
            // Frontmost: just paste into whatever has focus.
            DorisLog.voice.info("pasting into frontmost \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public)")
            paste(trimmed)
            if autoSubmit {
                try? await Task.sleep(nanoseconds: 100_000_000)
                pressReturn()
            }
        }
    }

    // MARK: - Steps

    private func activate(appURL: URL, bundleId: String) async throws {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        cfg.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: cfg)
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
               app.isFinishedLaunching {
                break
            }
        }
    }

    private func paste(_ text: String) {
        // Dictation into an app the typing helper watches is counted there
        // (it sees the synthetic ⌘V); anywhere else, count it here.
        if !TypingBridge.shared.countsFrontmost {
            ActivityRecorder.shared?.addWords(WordCount.count(text))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        synthesize(keyCode: 9, flags: .maskCommand)  // ⌘V
    }

    private func pressReturn() {
        synthesize(keyCode: 36, flags: [])
    }

    private func synthesize(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    private func ensureAccessibility(promptUser: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: promptUser ? kCFBooleanTrue : kCFBooleanFalse] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
