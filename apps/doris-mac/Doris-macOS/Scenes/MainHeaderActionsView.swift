import SwiftUI
import DorisCore
import DorisUI

/// The right-hand cluster of the main window's title bar: today's date,
/// the sync pill, and the light/dark toggle.
///
/// This is hosted as a **trailing** `NSTitlebarAccessoryViewController`
/// (see `MainWindowController`) rather than as a SwiftUI `.toolbar` item.
/// SwiftUI's toolbar placements don't honor leading/trailing separation in
/// this manually-hosted `NavigationSplitView` window — `.primaryAction`
/// bunched left and a lone `.principal` item centered — so the only reliable
/// way to pin these to the right edge is a native titlebar accessory.
///
/// Everything here reads singletons (`SyncSettings` / `ThemeSettings` via the
/// sub-views) or a static date, so it needs no shared window state.
struct MainHeaderActionsView: View {
    @ObservedObject private var theme = ThemeSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
            SyncNowToolbarButton(showsTime: false)
            ThemeToggleButton()
        }
        .padding(.trailing, 14)
        .padding(.leading, 8)
        .frame(height: 28)
        // Match the window's theme so the controls read correctly in both
        // light and dark (the accessory is a separate hosting view).
        .preferredColorScheme(theme.mode.colorScheme)
    }
}
