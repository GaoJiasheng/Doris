import AppKit
import DorisIPC
import DorisUI

@MainActor
enum ClickActionRouter {
    static func execute(_ action: ClickAction) {
        switch action {
        case .openURL(let url):
            // Use the configuration API with `activates = true` so the
            // target app actually comes to front. Plain `open(url:)`
            // from a `LSUIElement: true` agent app (Doris) hands the
            // URL to the target without granting it activation rights
            // — so e.g. clicking the "Claude task complete" banner
            // would silently deliver claude:// to an already-running
            // Claude.app without raising its window. Explicit
            // OpenConfiguration fixes that.
            openExternalURL(url)
        case .openNote(let id):
            // Open the main window on that note. Posted now (an open window
            // picks it up) and again a beat later (a window still mounting
            // isn't listening yet) — selecting the same note twice is a no-op.
            MainWindowController.shared.show()
            let post = { NotificationCenter.default.post(name: .dorisOpenNote, object: id) }
            post()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: post)
        case .runIntent(let name):
            if let url = URL(string: "doris://intent/\(name)") {
                NSWorkspace.shared.open(url)
            }
        case .markDone:
            break
        }
    }

    /// Open an arbitrary URL (typically a third-party app's scheme like
    /// claude:// / chatgpt:// / codex://) with explicit activation, so
    /// the target app comes to the foreground even when we're invoked
    /// from a menu-bar agent that's not itself an activatable app.
    private static func openExternalURL(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
    }
}
