import SwiftUI
import SwiftData
import DorisCore
import DorisIPC
import DorisUI

@main
struct DorisApp: App {
    @NSApplicationDelegateAdaptor(DorisAppDelegate.self) var appDelegate
    @ObservedObject private var theme = ThemeSettings.shared

    init() {
        #if DEBUG
        // Maintenance mode: push the schema to CloudKit Development, then exit.
        CloudKitSchemaInitializer.runIfRequested()
        #endif
    }

    var body: some Scene {
        // Doris is an `LSUIElement` agent — there is intentionally NO
        // SwiftUI `Window` / `WindowGroup` scene declared for the main
        // window. SwiftUI's `Window` scene auto-creates its NSWindow on
        // app launch / activation, regardless of our
        // `applicationShouldOpenUntitledFile` /
        // `applicationShouldHandleReopen` /
        // `applicationSupportsSecureRestorableState` /
        // `NSQuitAlwaysKeepsWindows` suppressors. We saw the user
        // clicking the menu-bar avatar and getting an unwanted main
        // window pop because of this.
        //
        // The main window is built and shown by the manually-managed
        // `MainWindowController` (Scenes/MainWindowController.swift),
        // wired through `AppCommands.openMainWindow`. Nothing in this
        // App body owns it. Settings stays SwiftUI because that scene
        // type is on-demand by design (only opens via Cmd+,).
        Settings {
            SettingsView()
                .modelContainer(DorisRuntime.shared.container)
                .preferredColorScheme(theme.mode.colorScheme)
        }
    }
}
