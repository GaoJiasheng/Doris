import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// "Deep work" main window. Same cyber vocabulary as the dropdown panel —
/// adaptive backdrop (dark or light, controlled by `ThemeSettings`), the
/// avatar hero in the sidebar header, neon-stroked surface cards in the
/// detail pane. Toolbar exposes the theme toggle so users can flip modes
/// without going to Settings.
///
/// Sidebar items: **Inbox** and **Notes**. The previous "Devices" placeholder
/// was retired since it never had functional content.
struct MainWindowView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    /// Observed here (not just at the controller's view construction)
    /// so flipping the theme via the toolbar / Settings triggers a
    /// SwiftUI re-evaluation. Without this binding the window kept
    /// whatever colorScheme was captured at first mount.
    @ObservedObject private var theme = ThemeSettings.shared
    /// Drives whether the avatar sidebar shows. Two-way synced with
    /// `columnVisibility` below: collapsing the sidebar (system toggle)
    /// persists the preference, and flipping it from Settings collapses
    /// / restores the sidebar here.
    @ObservedObject private var avatarSettings = AvatarSettings.shared
    @State private var tab: Tab = .today
    /// Lifted up from `MainNotesList` so the detail header (DORIS
    /// brand + tab buttons) can hide while editing — the editor gets
    /// the entire detail pane. Shared with `MainTodayView` too, so
    /// tapping a pinned/upcoming card on Today opens the same editor
    /// surface used by the TODO tab.
    @State private var editingNote: Note?
    /// Two-way bound so we can react to "sidebar collapsed" — when the
    /// avatar pane is hidden, the detail pane fills the window and
    /// the system draws traffic lights + sidebar-toggle inline at the
    /// detail's leading edge. The detail header needs to reserve room
    /// for those, otherwise the DORIS / tabs strip slides under them.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Tab: Hashable { case today, events, notes, tokens }

    var body: some View {
        ZStack {
            CyberBackground(haloIntensity: 0.7)
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Apply zoom *inside* each pane rather than wrapping
                // NavigationSplitView. The earlier "wrap the whole
                // thing in dorisZoom" approach put a GeometryReader
                // above NavigationSplitView, which broke its
                // internal hit-test routing — clicks on TODO/Events/
                // sync/theme stopped registering. Per-pane zoom
                // keeps NavSplitView's own layout/divider/responder
                // logic intact; each pane's content is what scales.
                sidebar.dorisZoom()
            } detail: {
                detail.dorisZoom()
            }
            .navigationSplitViewStyle(.balanced)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(theme.mode.colorScheme)
        // Restore the saved avatar-sidebar preference on open.
        .onAppear {
            columnVisibility = avatarSettings.avatarVisible ? .all : .detailOnly
        }
        // Settings toggle → collapse / restore the sidebar here.
        .onChange(of: avatarSettings.avatarVisible) { _, visible in
            withAnimation(.smooth(duration: 0.2)) {
                columnVisibility = visible ? .all : .detailOnly
            }
        }
        // User dragged/clicked the system sidebar toggle → remember it.
        // Guarded so the two onChange handlers don't ping-pong.
        .onChange(of: columnVisibility) { _, vis in
            let nowVisible = (vis != .detailOnly)
            if nowVisible != avatarSettings.avatarVisible {
                avatarSettings.avatarVisible = nowVisible
            }
        }
        // Cmd-+ / Cmd-− / Cmd-0 are intercepted by
        // `MainWindowController.installZoomKeyMonitor` (NSEvent
        // local monitor). The keypress mutates `ZoomSettings.shared.scale`;
        // each `dorisZoom()` above observes that setting and
        // re-renders with the new scale. Dragging the window border
        // is unchanged — it resizes the window's content area,
        // which `dorisZoom()` reflows into without changing the
        // visual font size. So Cmd-+ scales fonts/icons, drag
        // expands layout space.
    }

    // MARK: - Sidebar

    /// Sidebar is the avatar hero on the deep-space gradient. The
    /// background gradient still extends to the top edge of the window
    /// (under the transparent title bar) so the traffic-light buttons
    /// float over solid dark space — but the AvatarHero CONTENT itself
    /// respects the title-bar safe area, so the character + weather
    /// pill start a comfortable distance below the buttons instead of
    /// colliding with them.
    private var sidebar: some View {
        AvatarHero(compact: true, showWeather: true, selfChrome: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 240)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.04, blue: 0.10),
                        Color(red: 0.01, green: 0.01, blue: 0.04)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            )
    }

    private func sidebarItem(_ value: Tab, label: String, system: String) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            HStack(spacing: 10) {
                Image(systemName: system)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(CyberPalette.neonCyan) : AnyShapeStyle(Color.primary.opacity(0.6)))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.7)))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? CyberPalette.neonCyan.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? CyberPalette.neonCyan.opacity(0.4) : Color.clear, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            switch tab {
            case .today:  MainTodayView(editing: $editingNote, onOpenTokens: { tab = .tokens })
            case .events: MainEventsList()
            case .notes:  MainNotesList(editing: $editingNote)
            case .tokens: MainTokensView()
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The DORIS / tabs / sync / theme strip lives in the window TOOLBAR
        // (real title-bar controls), not as content under the title bar.
        // On macOS 26 the title-bar region swallows clicks aimed at content
        // placed beneath it via `.ignoresSafeArea(.top)`, but genuine toolbar
        // items (like the sidebar toggle) keep working — and they occupy the
        // title-bar row itself, so there's no empty band above the content.
        // Hidden while editing a note so the editor owns the whole pane.
        // Always shown (even while editing a note) so the title-bar row is
        // never empty — an empty toolbar left a big blank band above the
        // note/sub-task editor.
        // One full-width principal item: DORIS + tabs pinned LEFT, a flexible
        // spacer, then date + sync + theme pinned RIGHT. `.primaryAction`
        // wasn't right-aligning in this manually-hosted NavigationSplitView
        // toolbar (everything bunched left), so lay the two groups out
        // explicitly with a Spacer between them.
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    Text("DORIS")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .kerning(2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [CyberPalette.neonPink, CyberPalette.neonCyan],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 6) {
                        tabButton(.today, label: L("Today", "今日"), system: "sparkles")
                        tabButton(.notes, label: L("TODO", "TODO"), system: "checklist")
                        tabButton(.events, label: L("Events", "事件"), system: "tray.fill")
                        tabButton(.tokens, label: L("Tokens", "Token"), system: "bolt.fill")
                    }
                    Spacer(minLength: 24)
                    HStack(spacing: 10) {
                        Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.6))
                            .lineLimit(1)
                            .fixedSize()
                        SyncNowToolbarButton(showsTime: false)
                        ThemeToggleButton()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Right-pane header: DORIS brand on the left, tab buttons next to
    /// it, and the sync + theme actions tucked on the trailing edge.
    /// We pulled those two off the window toolbar so the title bar
    /// stays minimal and the whole "navigation strip" reads as one row.
    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            // DORIS wordmark — single line, with `.fixedSize` so SwiftUI
            // doesn't squeeze it letter-by-letter into a vertical column
            // when the toolbar fills up. The decorative "cyber helper /
            // 赛博助手" subtitle that used to live here was removed —
            // it duplicates the dock-bar app name and was the main
            // source of visual noise when the row got crowded.
            Text("DORIS")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .kerning(2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [CyberPalette.neonPink, CyberPalette.neonCyan],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 6) {
                // Today is the landing tab — first slot so it reads
                // as the primary surface. `sparkles` matches the
                // iOS empty-state icon and stays out of the way of
                // the theme toggle's sun/moon glyphs (which sit on
                // the trailing edge of the same strip).
                tabButton(.today, label: L("Today", "今日"), system: "sparkles")
                tabButton(.notes, label: L("TODO", "TODO"), system: "checklist")
                tabButton(.events, label: L("Events", "事件"), system: "tray.fill")
                tabButton(.tokens, label: L("Tokens", "Token"), system: "bolt.fill")
            }

            Spacer()

            // Right cluster: date stamp + actions. Putting the date
            // here (rather than between tabs and the spacer) groups
            // "info + actions" as one trailing unit and gives the
            // tab buttons room to breathe — at higher zoom levels
            // the previous middle-positioned date squeezed the tabs
            // hard enough that their labels collapsed vertically.
            // Abbreviated weekday ("Sat, May 16") keeps the stamp
            // narrow without losing day-of-week info.
            HStack(spacing: 10) {
                Text(Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
                SyncNowToolbarButton()
                ThemeToggleButton()
            }
        }
        // Leading padding reserves space for the traffic lights
        // (~78pt) + the sidebar-toggle button (which sits inset
        // further than expected — measured ~160pt total clearance
        // before content starts) when the sidebar is collapsed;
        // otherwise just the standard 18pt gutter (the avatar
        // sidebar covers that strip on its own).
        //
        // Match NavigationSplitView's faster non-bouncy spring with a
        // short `.smooth` so the padding finishes shrinking before
        // the sidebar finishes sliding in. With a longer duration
        // (0.3s) the header trailed the sidebar visibly on expand —
        // a "sticky" feel where content seemed to drift in late.
        // 0.18s lands just before NavigationSplitView's slide
        // settles, so by the time you can read the header it's
        // already at its final position.
        .padding(.leading, columnVisibility == .detailOnly ? 160 : 18)
        .padding(.trailing, 18)
        // Minimal top padding now that the strip sits just below the title
        // bar (the title-bar height itself is the only gap above it).
        .padding(.top, 3)
        .padding(.bottom, 12)
        .animation(.smooth(duration: 0.18), value: columnVisibility)
    }

    /// Capsule-style tab button. Selected = cyan-accented, unselected =
    /// dim primary. Same vocabulary as the dropdown panel's tab row so
    /// the two surfaces feel like one product.
    private func tabButton(_ value: Tab, label: String, system: String) -> some View {
        let isSelected = tab == value
        return Button {
            tab = value
            // Leave any open note editor so the tab actually switches (the
            // editor is shown whenever editingNote is set, regardless of tab).
            editingNote = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .kerning(0.4)
                    // Without these, SwiftUI compresses the label
                    // when the row gets crowded and the text breaks
                    // into one-character-per-line vertical stacks
                    // ("今日" → 今 / 日, "TODO" → T / O / D / O).
                    // `fixedSize` reserves the natural width; the
                    // surrounding Spacer absorbs any leftover slack.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(
                isSelected
                    ? AnyShapeStyle(Color.primary)
                    : AnyShapeStyle(Color.primary.opacity(0.55))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? CyberPalette.neonCyan.opacity(0.14) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? CyberPalette.neonCyan.opacity(0.45) : Color.clear, lineWidth: 0.6)
            )
            // Force the whole padded capsule to be hit-testable. Without
            // this, the unselected tab's `Color.clear` background means
            // SwiftUI only counts clicks that land on the text/icon
            // glyphs themselves — users had to aim precisely at the
            // letters and felt the tab "didn't respond" most of the time.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Events

private struct MainEventsList: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx

    /// Fetch only today's active messages on appear. Past-day archives
    /// are loaded lazily via `DayCollapsibleEventList`'s per-day
    /// disclosure groups. Was previously a full-history @Query which
    /// materialised every message on every body re-evaluation —
    /// noticeable lag once the Mac side accumulated more than a few
    /// hundred CLI notifications.
    @Query private var todayMessages: [Message]

    init() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let activeRaw = MessageState.active.rawValue
        _todayMessages = Query(
            filter: #Predicate<Message> { msg in
                msg.receivedAt >= startOfToday && msg.stateRaw == activeRaw
            },
            sort: [SortDescriptor(\Message.receivedAt, order: .reverse)]
        )
    }

    var body: some View {
        ScrollView {
            if todayMessages.isEmpty && !hasAnyMessage {
                emptyState
                    .padding(.top, 80)
            } else {
                DayCollapsibleEventList(today: todayMessages) { m in
                    EventRow(message: m)
                }
                .padding(20)
            }
        }
    }

    private var hasAnyMessage: Bool {
        var desc = FetchDescriptor<Message>()
        desc.fetchLimit = 1
        let count = (try? ctx.fetchCount(desc)) ?? 0
        return count > 0
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.system(size: 36))
                .foregroundStyle(.primary.opacity(0.4))
            Text(L("No events yet", "暂无事件"))
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.7))
            Text(L("CLI pushes, share extension drops, and cross-device events will land here.",
                   "CLI 通知、Share 扩展、跨设备事件都会出现在这里。"))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }
}

private struct EventRow: View {
    let message: Message

    var body: some View {
        let levelTint = EventLevelStyle.color(for: message.level)
        CyberCard {
            HStack(alignment: .top, spacing: 12) {
                // Severity stripe — full for critical/reminder, dimmed
                // for info via the shared `intensity(for:)` helper so
                // info events stay quietly in the background.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(levelTint)
                    .frame(width: 3)
                    .opacity(EventLevelStyle.intensity(for: message.level))

                Image(systemName: message.iconName ?? message.source.sfSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(levelTint.opacity(EventLevelStyle.intensity(for: message.level)))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(message.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if message.level != .info {
                            levelBadge(for: message.level, tint: levelTint)
                        }
                    }
                    if let body = message.bodyMarkdown, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineLimit(3)
                    }
                    HStack(spacing: 6) {
                        Text(message.source.displayName)
                            .font(.caption2)
                            .foregroundStyle(.primary.opacity(0.55))
                        Text("·")
                            .foregroundStyle(.primary.opacity(0.4))
                        // Absolute timestamp; see EventsRowView for
                        // rationale.
                        Text(message.receivedAt,
                             format: .dateTime.month(.twoDigits).day(.twoDigits)
                                              .hour(.twoDigits(amPM: .omitted))
                                              .minute(.twoDigits))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.primary.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func levelBadge(for level: EventLevel, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: level.sfSymbol)
                .font(.system(size: 9, weight: .semibold))
            Text(level.displayName.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .kerning(0.5)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.15)))
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 0.5))
    }
}

// MARK: - Notes

private struct MainNotesList: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var notes: [Note]

    @Binding var editing: Note?
    /// Plain @State (not @FocusState): the TODO rows are AppKit title
    /// fields that drive first-responder themselves. A @FocusState set
    /// with no matching `.focused()` modifier reverts to nil, so the
    /// newly-created row never received the caret.
    @State private var focusedNoteID: UUID?
    /// A note we just created (Enter on a row, or the add button) that we
    /// want to focus *once it actually appears* in `sortedNotes`. The
    /// SwiftData @Query refresh is async, so assigning `focusedNoteID`
    /// straight after insert races the new row's first render and the
    /// focus is silently dropped — we apply it from `.onChange` instead.
    @State private var pendingFocusNoteID: UUID?
    /// Debounce guard: tracks when the last note was created so rapid
    /// successive calls to addNoteAfter (e.g. Enter keypress leaking into
    /// the newly-focused row) are ignored within a 300ms window.
    @State private var lastNoteAddedAt: Date = .distantPast
    @State private var filter: TodoFilter = .active
    @State private var confirmingEmptyTrash = false

    /// Three-partition filter: trash > archived > active. Each row sits
    /// in exactly one. Sort key flips by view: trash by deletedAt,
    /// archived by archivedAt, active by pin/done/createdAt.
    private var sortedNotes: [Note] {
        let filtered = notes.filter { n in
            switch filter {
            case .trash:    return n.deleted
            case .archived: return !n.deleted && n.archived
            case .active:   return !n.deleted && !n.archived
            }
        }
        switch filter {
        case .trash:
            return filtered.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        case .archived:
            return filtered.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        case .active:
            return filtered.sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
                if lhs.done != rhs.done     { return !lhs.done && rhs.done }
                if lhs.order != rhs.order   { return lhs.order < rhs.order }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    /// Reorder: place `draggedID` right before `targetID`. Renumbers
    /// every visible row's `order` field — bulletproof against the
    /// "averaging two equal orders" collision when most rows still
    /// have legacy order = 0.
    private func moveDraggedBefore(_ targetID: UUID, dragged draggedID: UUID) {
        let visible = sortedNotes
        guard visible.contains(where: { $0.id == targetID }),
              let dragged = visible.first(where: { $0.id == draggedID }) else { return }
        var reordered = visible.filter { $0.id != draggedID }
        let insertIdx = reordered.firstIndex(where: { $0.id == targetID }) ?? 0
        reordered.insert(dragged, at: insertIdx)
        for (i, n) in reordered.enumerated() {
            n.order = Double(i)
        }
        dragged.updatedAt = Date()
        try? ctx.save()
    }

    private var doneActiveCount: Int {
        notes.filter { !$0.deleted && !$0.archived && $0.done }.count
    }
    private var trashCount: Int {
        notes.filter { $0.deleted }.count
    }

    var body: some View {
        Group {
            if let editing {
                InlineNoteEditor(note: editing) {
                    self.editing = nil
                }
            } else {
                listBody
            }
        }
    }

    private var listBody: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ScrollView {
                // spacing: 0 — adjacent rows touch, no dead non-clickable
                // strip between them. The row's own internal vertical
                // padding (bumped slightly) gives a comfortable click
                // target while keeping the list visually dense.
                VStack(spacing: 0) {
                    if sortedNotes.isEmpty {
                        emptyState.padding(.top, 60)
                    } else {
                        ForEach(sortedNotes) { n in
                            TodoRow(
                                note: n,
                                focused: $focusedNoteID,
                                onSubmit: { addNoteAfter(n) },
                                onExpand: { editing = n },
                                onDeleteEmpty: { deleteEmptyAndFocusPrev(n) },
                                onDropBefore: { dragged in
                                    moveDraggedBefore(n.id, dragged: dragged)
                                },
                                onMoveUp: { focusAdjacentNote(of: n, direction: -1) },
                                onMoveDown: { focusAdjacentNote(of: n, direction: +1) }
                            )
                        }
                    }
                    if filter == .active {
                        addQuickButton.padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        // Apply deferred focus once the freshly-created note shows up in
        // the list. Fires only on structural changes (insert/remove/
        // reorder) — editing a title leaves identity + order unchanged, so
        // this stays quiet during typing.
        .onChange(of: sortedNotes) { _, newValue in
            guard let target = pendingFocusNoteID,
                  newValue.contains(where: { $0.id == target }) else { return }
            pendingFocusNoteID = nil
            focusedNoteID = target
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            filterChip(.active,   label: L("Active",   "未归档"), icon: "checklist")
            filterChip(.archived, label: L("Archived", "已归档"), icon: "archivebox")
            filterChip(.trash,    label: L("Trash",    "回收站"), icon: "trash")
            Spacer()
            bulkAction
        }
        .alert(L("Empty trash?", "清空回收站?"),
               isPresented: $confirmingEmptyTrash) {
            Button(L("Empty (\(trashCount))", "清空 (\(trashCount))"), role: .destructive) {
                emptyTrash()
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("Items in the trash will be permanently deleted and can't be recovered.",
                   "回收站中的任务将被彻底删除,无法恢复。"))
        }
    }

    @ViewBuilder
    private var bulkAction: some View {
        if filter == .active && doneActiveCount > 0 {
            bulkButton(
                icon: "tray.full",
                label: L("Archive done (\(doneActiveCount))",
                         "归档已完成 (\(doneActiveCount))"),
                tint: CyberPalette.neonCyan,
                help: L("Move all completed tasks to archive",
                        "把所有已完成任务移到归档")
            ) { archiveAllDone() }
        } else if filter == .trash && trashCount > 0 {
            bulkButton(
                icon: "trash.slash",
                label: L("Empty (\(trashCount))", "清空 (\(trashCount))"),
                tint: CyberPalette.neonPink,
                help: L("Permanently delete every item in trash",
                        "彻底删除回收站中所有任务")
            ) { confirmingEmptyTrash = true }
        }
    }

    private func bulkButton(icon: String, label: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.10)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func filterChip(_ value: TodoFilter, label: String, icon: String) -> some View {
        let selected = (filter == value)
        return Button { filter = value } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.caption.weight(selected ? .semibold : .regular))
            }
            .foregroundStyle(selected
                             ? Color.primary
                             : Color.primary.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(selected
                               ? Color.primary.opacity(0.10)
                               : Color.clear)
            )
            .overlay(
                Capsule().stroke(selected
                                 ? Color.primary.opacity(0.20)
                                 : Color.primary.opacity(0.10),
                                 lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Bulk archive: stamps every active+done note as archived in one
    /// pass. Morning routine: yesterday's done items disappear with one
    /// click; undone ones stay rolled over to today.
    private func archiveAllDone() {
        let now = Date()
        for n in notes where !n.deleted && !n.archived && n.done {
            n.archived = true
            n.archivedAt = now
            n.updatedAt = now
        }
        try? ctx.save()
    }

    private func emptyTrash() {
        // `n.deleted` is already the soft-delete flag — by the time a
        // note is in Trash it's already deleted=true. To "empty" the
        // trash we want a hard delete via CloudKit, but `ctx.delete`
        // races against other devices' mirror (same root cause as the
        // Settings Recently Deleted bug: notes resurrect when iOS
        // still has them in its local store and uploads its copy
        // before our tombstone propagates).
        //
        // Workaround: bump deletedAt to 31 days ago so `purgeTombstones`
        // picks them up on the next 60-second poke. By then all
        // devices have surely seen the deleted=true flag, so the hard
        // delete is safe. User loses "instant emptiness" but gains
        // "actually deleted, doesn't come back".
        let purgeMarker = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        for n in notes where n.deleted {
            n.deletedAt = purgeMarker
            n.updatedAt = purgeMarker
        }
        try? ctx.save()
    }

    private var addQuickButton: some View {
        HStack {
            Button {
                addNoteAfter(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(L("Add task", "新增任务"))
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(CyberPalette.neonCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(CyberPalette.neonCyan.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(CyberPalette.neonCyan.opacity(0.35), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// Insert an empty TODO at the right position:
    ///   - `previous` non-nil → right AFTER `previous` (Enter on a row).
    ///     `createdAt` is bumped 1ms past the previous row so the
    ///     `createdAt ASC` sort lands the new row in the next slot.
    ///   - `previous` nil → at the very BOTTOM of the list (button click).
    ///     `createdAt` jumps past every existing row.
    private func addNoteAfter(_ previous: Note?) {
        // Debounce: ignore rapid successive calls within 300ms. The AppKit
        // field editor can fire insertNewline AND then the newly-focused row
        // may receive a stale Return event from the event queue — without
        // this guard that creates two rows in quick succession.
        let now = Date()
        guard now.timeIntervalSince(lastNoteAddedAt) > 0.3 else { return }
        lastNoteAddedAt = now

        let n = Note(title: "")
        // Position the new row by `order` so it lands directly BELOW
        // `previous` (or at the end when added from the + button). The
        // active sort is pinned > done > order > createdAt; once any row
        // has a non-zero `order` (after a drag) a fresh note left at
        // order 0 would jump to the top. Renumber the visible sequence —
        // same approach as drag-reorder — so the insert point is exact.
        // Pinned rows keep their relative order (they're already at the
        // front of the sequence), so the Today pinned grid isn't disturbed.
        var seq = sortedNotes
        if let previous, let pIdx = seq.firstIndex(where: { $0.id == previous.id }) {
            seq.insert(n, at: pIdx + 1)
        } else {
            seq.append(n)
        }
        ctx.insert(n)
        for (i, note) in seq.enumerated() { note.order = Double(i) }
        try? ctx.save()
        // Don't focus here — the row isn't in `sortedNotes` yet (async
        // @Query refresh). `.onChange(of: sortedNotes)` lands the cursor
        // in the new row the moment it renders, at the start of its
        // (empty) title field.
        pendingFocusNoteID = n.id
    }

    /// Backspace on an empty task row → delete it and land the caret at
    /// the END of the previous row. No-op on the first row (nothing to
    /// merge into). Mirrors the checklist editor's backspace-merge.
    private func focusAdjacentNote(of n: Note, direction: Int) {
        let rows = sortedNotes
        guard let idx = rows.firstIndex(where: { $0.id == n.id }) else { return }
        let next = idx + direction
        guard rows.indices.contains(next) else { return }
        let targetID = rows[next].id
        // Defer to the next runloop — setting focus synchronously while we're
        // still inside the field editor's key-event handling doesn't reliably
        // move the first responder (same reason deleteEmptyAndFocusPrev defers).
        DispatchQueue.main.async { focusedNoteID = targetID }
    }

    private func deleteEmptyAndFocusPrev(_ n: Note) {
        let rows = sortedNotes
        guard let idx = rows.firstIndex(where: { $0.id == n.id }), idx > 0 else { return }
        let prev = rows[idx - 1]
        ctx.delete(n)
        try? ctx.save()
        // AppKit title field self-focuses + drops the caret at the end
        // when focusedNoteID matches; pendingFocus applies it once the
        // list settles after the delete.
        pendingFocusNoteID = prev.id
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: emptyIcon)
                .font(.system(size: 36))
                .foregroundStyle(.primary.opacity(0.4))
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.7))
            Text(emptyHint)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var emptyIcon: String {
        switch filter {
        case .active:   return "checklist"
        case .archived: return "archivebox"
        case .trash:    return "trash"
        }
    }
    private var emptyTitle: String {
        switch filter {
        case .active:   return L("No tasks yet",       "暂无任务")
        case .archived: return L("No archived tasks",  "暂无归档任务")
        case .trash:    return L("Trash is empty",     "回收站为空")
        }
    }
    private var emptyHint: String {
        switch filter {
        case .active:
            return L("Press \"+ Add task\" or just start typing.",
                     "点击下方「+ 新增任务」开始。")
        case .archived:
            return L("Tasks you archive will show up here. Use the box icon on a row, or the bulk button on the active list.",
                     "归档的任务会出现在这里。点行尾的箱子图标,或在「未归档」列表用批量按钮。")
        case .trash:
            return L("Deleted tasks land here, recoverable until you Empty trash.",
                     "删除的任务会出现在这里,清空之前都可以还原。")
        }
    }
}
