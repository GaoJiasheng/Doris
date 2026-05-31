import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// iOS Today tab — three blocks:
///   1. Weather card — full-width ambient weather panel
///   2. Pinned tasks — 2-column grid of compact cards
///   3. Calendar — upcoming / overdue notes sorted by dueDate
///
/// The three card types (`TodayWeatherCard`, `TodayPinnedCard`,
/// `TodayCalendarRow`) live in `DorisUI/Today/TodayComponents.swift`
/// and are shared with the macOS `MainTodayView` so visual tweaks land
/// on both platforms from one file.
struct TodayScreen: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var weather = WeatherViewModel.shared
    @Environment(\.modelContext) private var ctx

    @Query(
        filter: #Predicate<Note> { note in !note.archived },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var allNotes: [Note]

    @State private var path = NavigationPath()

    /// Pinned notes sorted by urgency:
    ///   1. Notes with a `dueDate` come first, sorted ascending (most
    ///      overdue → today → soonest future).
    ///   2. Notes without a `dueDate` come after, sorted by `updatedAt`
    ///      descending (most recently touched first).
    private var pinnedNotes: [Note] {
        allNotes
            .filter { $0.pinned }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (l?, r?): return l < r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.updatedAt > b.updatedAt
                }
            }
    }

    /// Same filter as the macOS Today view — past + completed rows are
    /// hidden by default; overdue (past + not done) stays visible. The
    /// `isPastAndCompleted` helper lives on Note so the rule is shared.
    private var calendarNotes: [Note] {
        allNotes
            .filter { $0.dueDate != nil && !$0.isPastAndCompleted() }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // ── Block 1: Weather ─────────────────────────────────
                    TodayWeatherCard(vm: weather)

                    // ── Block 2: Pinned tasks ─────────────────────────────
                    if !pinnedNotes.isEmpty {
                        // Pink for pinned (attention / user-flagged),
                        // cyan for upcoming (calmer scheduled stuff).
                        // Swapped from the original to read warmer.
                        sectionHeader(
                            icon: "pin.fill",
                            title: L("Pinned", "置顶"),
                            tint: CyberPalette.neonPink
                        )
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            ForEach(pinnedNotes) { n in
                                Button { path.append(n.id) } label: {
                                    TodayPinnedCard(note: n)
                                }
                                .buttonStyle(.plain)
                                // Long-press = the same actions the
                                // Mac right-click surfaces (Schedule
                                // submenu, Mark done, Done & archive,
                                // Pin, Archive, Move to trash).
                                .noteContextMenu(for: n) { path.append(n.id) }
                            }
                        }
                    }

                    // ── Block 3: Calendar ─────────────────────────────────
                    if !calendarNotes.isEmpty {
                        sectionHeader(
                            icon: "calendar",
                            title: L("Upcoming", "日程"),
                            tint: CyberPalette.neonCyan
                        )
                        VStack(spacing: 8) {
                            ForEach(calendarNotes) { n in
                                NavigationLink(value: n.id) {
                                    TodayCalendarRow(note: n)
                                }
                                .buttonStyle(.plain)
                                .noteContextMenu(for: n) { path.append(n.id) }
                            }
                        }
                    }

                    // Empty state (no pinned, no calendar)
                    if pinnedNotes.isEmpty && calendarNotes.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ThemeToggleButton() }
                ToolbarItem(placement: .principal) { navTitle }
            }
            .navigationDestination(for: UUID.self) { id in
                if let note = allNotes.first(where: { $0.id == id }) {
                    NoteDetailScreen(note: note) {
                        if !path.isEmpty { path.removeLast() }
                    }
                }
            }
            .onAppear { weather.start() }
        }
    }

    // MARK: - Nav title

    private var navTitle: some View {
        VStack(spacing: 2) {
            Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(L("TODAY", "今日"))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.85))
                .kerning(3)
        }
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .kerning(2)
            Rectangle()
                .fill(tint.opacity(0.18))
                .frame(height: 0.6)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.45))
            Text(L("All clear", "今日清净"))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.65))
            Text(L("Pin a note or set a due date to see it here.",
                   "置顶笔记或设定截止日期即可出现在这里。"))
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
