import SwiftUI
import DorisCore
import DorisUI

/// Top-level tab bar. Order: Today / Notes / Events / Settings.
/// Today is the agenda hero (weather + pinned + calendar preview).
/// Notes is the primary writing surface. Events is the cross-device
/// notifications inbox. Settings was lifted from a Notes-toolbar sheet
/// into its own tab so the Notes top bar can stay focused on quick
/// actions (calendar timeline + new note).
struct RootTabView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var focus = FocusTimer.shared
    @State private var selection: Tab = .today
    /// Whether the full-screen focus dial is up. Auto-raised when a session
    /// starts; the dial's ✕ lowers it WITHOUT stopping the clock, and the
    /// return chip raises it again.
    @State private var showingFocus = false

    enum Tab: Hashable { case today, notes, events, settings }

    var body: some View {
        tabs
            .fullScreenCover(isPresented: $showingFocus) {
                FocusFullScreenView { showingFocus = false }
            }
            // Starting a focus (from a task's context menu or a checklist
            // row) takes you straight to the dial.
            .onChange(of: focus.session?.startedAt) { _, started in
                if started != nil { showingFocus = true }
            }
    }

    /// The "back to the focus dial" chip.
    ///
    /// A bottom **safe-area inset**, not a floating overlay: some screens pin
    /// content to the bottom (Notes' search field is its own bottom inset),
    /// and an overlay landed right on top of it. As an inset it reserves its
    /// own band and the screen's content lays out above it.
    ///
    /// Only shown when the dial is dismissed but a session is still live —
    /// otherwise it would duplicate the dial.
    @ViewBuilder
    private var focusChip: some View {
        if !showingFocus, focus.session != nil {
            FocusReturnChip { showingFocus = true }
                .padding(.vertical, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            TodayScreen()
                .tabItem {
                    Label(L("Today", "今日"), systemImage: "sun.max.fill")
                }
                .tag(Tab.today)

            NotesScreen()
                .tabItem {
                    Label(L("Notes", "笔记"), systemImage: "note.text")
                }
                .tag(Tab.notes)

            EventsScreen()
                .tabItem {
                    Label(L("Events", "事件"), systemImage: "tray.fill")
                }
                .tag(Tab.events)

            SettingsScreen()
                .tabItem {
                    Label(L("Settings", "设置"), systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(CyberPalette.neonCyan)
        // Floating, not a safe-area inset: an inset on the TabView lands on
        // top of the tab bar, and an inset on a tab doesn't reach that tab's
        // own bottom inset (Notes' search field), so it overlapped either way.
        // The offset clears the tab bar AND Notes' search field, the two
        // things pinned below it.
        .overlay(alignment: .bottom) {
            focusChip.padding(.bottom, 104)
        }
        .animation(.smooth(duration: 0.25), value: focus.session != nil)
    }
}
