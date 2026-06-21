import AppKit
import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Manually-managed main window. Replaces the SwiftUI `Window("Doris",
/// id: "main")` scene because that scene was auto-instantiating its
/// window on app launch / activation despite our four
/// `applicationShouldOpenUntitledFile` / `NSQuitAlwaysKeepsWindows` /
/// `applicationShouldHandleReopen` / `applicationSupportsSecureRestorableState`
/// suppressors. SwiftUI's `Window` scene type maintains its own
/// activation reflexes that those overrides don't fully reach.
///
/// With this controller:
///   - Nothing happens at launch — the window object isn't even created.
///   - First call to `show()` lazily builds the `NSWindow` +
///     `NSHostingController(MainWindowView)` and orders it front.
///   - Subsequent calls to `show()` reuse the same instance (single-window
///     semantics, like the previous `Window` scene gave us).
///   - Closing the window doesn't quit the app — the controller keeps
///     the (hidden) window around so the next `show()` is instant and
///     state-preserving.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    /// Open the main window if it doesn't exist yet, or bring it to
    /// front if it does. Always activates the app so the window comes
    /// into focus (needed because Doris is `LSUIElement: true` — it's
    /// not normally activatable by clicking the menu-bar avatar).
    ///
    /// `preferredScreen` is the display the user just interacted with
    /// (typically the screen where the menu-bar dropdown was open).
    /// On first show we center the window on that screen; on
    /// re-show, we move the existing window over if it isn't already
    /// on the right display, so users with multi-monitor setups don't
    /// get the main window left behind on whatever screen it was last
    /// closed on.
    func show(preferredScreen: NSScreen? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            if let screen = preferredScreen, window.screen != screen {
                centerWindow(window, on: screen)
            }
            window.makeKeyAndOrderFront(nil)
            scheduleGreetOnNextRunloop()
            return
        }

        let container = DorisRuntime.shared.container
        // `MainWindowView` observes `ThemeSettings` itself and applies
        // `.preferredColorScheme` reactively — don't apply it here too
        // (a static modifier at construction time wins, freezing the
        // window to whatever theme was active when first opened).
        let root = MainWindowView()
            .modelContainer(container)
        let host = NSHostingController(rootView: root)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        win.title = "Doris"
        // Hide the title text and make the title bar transparent so the
        // content view extends edge-to-edge under it. Combined with
        // `.fullSizeContentView`, this lets the DORIS / tabs / sync /
        // theme nav strip sit at the very top of the window with only
        // the traffic lights floating over the dark sidebar.
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        // No hairline under the title bar — the nav strip now sits just
        // below the title bar (it can't go under it on macOS 26 without
        // losing clicks), so a separator would draw a visible empty band.
        // With it off + the CyberBackground filling behind, the title-bar
        // height blends into the content.
        win.titlebarSeparatorStyle = .none
        // Header lives in the toolbar (DORIS / tabs / sync / theme). Unified
        // style keeps it in the title-bar row so there's no extra empty band.
        win.toolbarStyle = .unified
        win.contentViewController = host

        // Pin the date / sync / theme controls to the title bar's TRAILING
        // edge via a native titlebar accessory. SwiftUI's `.toolbar`
        // placements don't right-align in this manually-hosted
        // NavigationSplitView (`.primaryAction` bunched left next to the tabs,
        // a lone `.principal` item centered), so the brand + tabs stay in the
        // SwiftUI toolbar (leading) and the actions live here (trailing).
        let actionsHost = NSHostingView(rootView: MainHeaderActionsView())
        actionsHost.frame = NSRect(origin: .zero, size: actionsHost.fittingSize)
        let actionsVC = NSTitlebarAccessoryViewController()
        actionsVC.view = actionsHost
        actionsVC.layoutAttribute = .trailing
        win.addTitlebarAccessoryViewController(actionsVC)

        win.identifier = NSUserInterfaceItemIdentifier("doris-main")
        // Match the previous SwiftUI Window's full-screen behavior — the
        // green title-bar button enters full-screen instead of zoom.
        win.collectionBehavior.remove(.fullScreenNone)
        win.collectionBehavior.remove(.fullScreenAuxiliary)
        win.collectionBehavior.insert(.fullScreenPrimary)
        win.isReleasedWhenClosed = false
        win.delegate = self
        if let screen = preferredScreen {
            centerWindow(win, on: screen)
        } else {
            win.center()
        }

        self.window = win
        win.makeKeyAndOrderFront(nil)
        scheduleGreetOnNextRunloop()
    }

    /// Fire a hero greeting one tick after the window is shown.
    ///
    /// The two-step delay matters: we have to wait for AppKit to finish
    /// `makeKeyAndOrderFront` AND for SwiftUI to mount the hosting view
    /// tree (so `AvatarHero`'s `.onChange(of: heroEvents.lastGreeting)`
    /// observer is attached) before bumping the bus. If we bumped it
    /// synchronously, the change would happen before the observer was
    /// in place and the greeting would be silently missed.
    ///
    /// 200 ms is the same hand-tuned delay the dropdown panel uses for
    /// the same reason; both surfaces share the singleton `HeroEvents`
    /// bus + the same `AvatarHero` listener pattern.
    private func scheduleGreetOnNextRunloop() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            HeroEvents.shared.greet()
        }
    }

    private func centerWindow(_ win: NSWindow, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = win.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        win.setFrameOrigin(origin)
    }

    // MARK: - NSWindowDelegate

    /// Closing the window just hides it — keep the instance around for
    /// fast re-open. Returning `false` would block the close; we want
    /// the window to actually disappear, so return `true` and let
    /// AppKit hide it (with `isReleasedWhenClosed = false` the NSWindow
    /// object survives the close and can be ordered-front again).
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}
