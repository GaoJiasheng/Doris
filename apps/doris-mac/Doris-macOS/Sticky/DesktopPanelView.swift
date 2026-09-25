import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Always-on-desktop "今日" card: pinned (置顶 + 长期) plus what is due
/// today or overdue (日程), with inline done toggles. Anything dated after
/// today is folded under a collapsed "之后 N 项" row. Live via @Query so it
/// tracks edits made anywhere in the app. Hosted in a floating StickyPanel
/// by DesktopPanelController.
///
/// Deliberately minimal: the only chrome is the title, date and open
/// count. Window options (always-on-top, opacity, hide) live in the
/// right-click menu. The main window's Today tab has room for the full
/// look-ahead; this card and the iOS Tasks widget share the narrower rule.
struct DesktopPanelView: View {
    let onClose: () -> Void
    /// Push the "always on top" toggle to the hosting NSPanel's window
    /// level live — the controller owns the panel, the view only knows
    /// the setting. Opacity is applied in-view, so it needs no hook.
    var onAlwaysOnTopChanged: (Bool) -> Void = { _ in }
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var theme = ThemeSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var panelSettings = DesktopPanelSettings.shared
    /// Start of the current day. Every date bucket below reads it, so
    /// bumping it at midnight (see `.onReceive` on the body) re-sorts a
    /// card left open overnight — nothing else would trigger a redraw.
    @State private var today = Calendar.current.startOfDay(for: Date())

    // 长期 violet — same accent the main Today view uses for the bucket.
    private let longTermViolet = Color(red: 0.62, green: 0.51, blue: 1.0)

    @Query(
        filter: #Predicate<Note> { !$0.archived && !$0.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var allNotes: [Note]

    private var regularPinned: [Note] {
        allNotes.filter { $0.pinned && !$0.longTerm }.sorted(by: pinnedOrder)
    }

    private var longTermNotes: [Note] {
        allNotes.filter { $0.pinned && $0.longTerm }.sorted(by: pinnedOrder)
    }

    /// Unpinned notes with a date that are still worth showing: past-and-
    /// done rows are dropped, overdue ones kept.
    private var datedNotes: [Note] {
        allNotes
            .filter { !$0.pinned && $0.dueDate != nil && !$0.isPastAndCompleted(now: today) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Due today or overdue — what a card titled 今日 is actually about.
    /// Overdue rows sort to the top on their own, being the earliest.
    private var dueNotes: [Note] {
        datedNotes.filter { !$0.isDueAfterToday(now: today) }
    }

    /// Dated after today. This used to be listed straight under 日程,
    /// which is what made the card read as mislabelled: next week sat
    /// beside today with nothing to tell them apart.
    private var laterNotes: [Note] {
        datedNotes.filter { $0.isDueAfterToday(now: today) }
    }

    private func pinnedOrder(_ a: Note, _ b: Note) -> Bool {
        if a.order != b.order { return a.order < b.order }
        return a.updatedAt > b.updatedAt
    }

    private var isEmpty: Bool {
        regularPinned.isEmpty && longTermNotes.isEmpty && dueNotes.isEmpty && laterNotes.isEmpty
    }

    /// Header chip: what is still open today. Finished rows stay listed
    /// (struck through) but aren't counted, and the folded later rows
    /// carry their own count.
    private var openCount: Int {
        (regularPinned + longTermNotes + dueNotes).filter { !$0.isCompleted }.count
    }

    /// Set when the user taps a task to edit it. Swaps the whole panel to
    /// an in-place `InlineNoteEditor` — the SAME full-pane editor the notch
    /// dropdown (`AnchorView`) uses — since that's the only surface where a
    /// note's sub-tasks / text can actually be changed. The panel is a
    /// key-capable `StickyPanel`, so the editor's text fields are editable.
    @State private var editingNote: Note?

    var body: some View {
        Group {
            if let editingNote {
                InlineNoteEditor(note: editingNote) { self.editingNote = nil }
                    .padding(6)
            } else {
                dashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Only the background + edge fade with the opacity setting; the
        // tasks stay fully opaque so a see-through card is still readable.
        .background(panelBackground.opacity(panelSettings.opacity))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CyberPalette.dimPanelStroke, lineWidth: 0.9)
                .opacity(panelSettings.opacity)
        )
        .preferredColorScheme(theme.mode.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .receive(on: RunLoop.main)) { _ in
            today = Calendar.current.startOfDay(for: Date())
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            Divider().overlay(Color.primary.opacity(0.08))

            if isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 11) {
                        if !regularPinned.isEmpty {
                            section(L("Pinned", "置顶"), icon: "pin.fill",
                                    tint: CyberPalette.neonPink, notes: regularPinned)
                        }
                        if !longTermNotes.isEmpty {
                            section(L("Long-term", "长期"), icon: "infinity",
                                    tint: longTermViolet, notes: longTermNotes)
                        }
                        if !dueNotes.isEmpty || !laterNotes.isEmpty {
                            section(L("Due", "日程"), icon: "calendar",
                                    tint: CyberPalette.neonCyan, notes: dueNotes)
                            if !laterNotes.isEmpty { laterDisclosure }
                        }
                    }
                }
            }
        }
        .padding(12)
        // Window options live here so the card itself stays a plain list.
        // `contentShape` makes the gaps between rows right-clickable too.
        .contentShape(Rectangle())
        .contextMenu { panelMenu }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { AppCommands.openMainWindow() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CyberPalette.neonCyan)
                    Text(L("Doris · Today", "Doris · 今日"))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Open main window · right-click for options",
                    "打开主窗口 · 右键查看更多选项"))
            Spacer()
            Text(today.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.5))
            if openCount > 0 {
                Text("\(openCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CyberPalette.neonCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(CyberPalette.neonCyan.opacity(0.16)))
            }
        }
    }

    // MARK: Right-click menu

    /// A menu can't host the live slider the old inline strip had, so
    /// opacity is a handful of stops. The last is the same floor the
    /// slider enforced — below it the card is hard to find again.
    private static let opacityStops: [Double] = [1.0, 0.85, 0.7, 0.5, DesktopPanelSettings.minOpacity]

    @ViewBuilder
    private var panelMenu: some View {
        Button(L("Open Main Window", "打开主窗口")) { AppCommands.openMainWindow() }
        Divider()
        Toggle(L("Always on Top", "总在最前"), isOn: Binding(
            get: { panelSettings.alwaysOnTop },
            set: { on in
                panelSettings.alwaysOnTop = on   // persist
                onAlwaysOnTopChanged(on)         // apply to the window live
            }
        ))
        Picker(L("Background Opacity", "背景不透明度"), selection: Binding(
            // Snap for display, so a value left over from the old slider
            // (say 0.63) still shows a checkmark on its nearest stop.
            get: {
                let o = panelSettings.opacity
                return Self.opacityStops.min { abs($0 - o) < abs($1 - o) } ?? 1.0
            },
            set: { panelSettings.opacity = $0 }
        )) {
            ForEach(Self.opacityStops, id: \.self) { v in
                Text("\(Int((v * 100).rounded()))%").tag(v)
            }
        }
        Divider()
        Button(L("Hide Desktop Panel", "隐藏桌面面板"), action: onClose)
    }

    // MARK: Later (folded)

    /// "之后 N 项" — collapsed by default, remembered across launches.
    /// Expanded rows always show their date (see `trailing`), since no
    /// section header says which day they fall on.
    @ViewBuilder
    private var laterDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { panelSettings.laterExpanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(panelSettings.laterExpanded ? 90 : 0))
                Text(L("Later · \(laterNotes.count)", "之后 \(laterNotes.count) 项"))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.primary.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.top, dueNotes.isEmpty ? 0 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if panelSettings.laterExpanded {
            ForEach(laterNotes) { row($0, tint: CyberPalette.neonCyan) }
        }
    }

    // MARK: Section

    @ViewBuilder
    private func section(_ title: String, icon: String, tint: Color, notes: [Note]) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(tint)
        }
        ForEach(notes) { row($0, tint: tint) }
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ note: Note, tint: Color) -> some View {
        HStack(spacing: 8) {
            // Section accent rail.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(note.isCompleted ? AnyShapeStyle(CyberPalette.doneAccent.opacity(0.4))
                                       : AnyShapeStyle(tint))
                .frame(width: 3, height: 16)

            Button {
                let now = Date()
                note.done.toggle()
                note.completedAt = note.done ? now : nil
                note.updatedAt = now
                try? ctx.save()
            } label: {
                Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(note.isCompleted ? AnyShapeStyle(CyberPalette.doneAccent)
                                                      : AnyShapeStyle(tint))
            }
            .buttonStyle(.plain)
            .help(note.isCompleted ? L("Mark not done", "标为未完成")
                                   : L("Mark done", "标记完成"))

            // Tap the title / meta — everything except the done circle —
            // to open the note for editing. This is the entry point to a
            // task's sub-tasks (the checklist) and its text; the row was
            // otherwise a read-only glance with just the done toggle.
            Button { editingNote = note } label: {
                HStack(spacing: 8) {
                    Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .strikethrough(note.isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                        .foregroundStyle(note.isCompleted
                            ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.42))
                            : AnyShapeStyle(HierarchicalShapeStyle.primary))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    trailing(note, tint: tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Edit task", "编辑任务"))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(note.isCompleted ? 0.0 : 0.06))
        )
    }

    /// Checklist progress and the date, each shown on its own merits.
    ///
    /// These used to share one slot — progress if there was a checklist,
    /// otherwise the date — so a task with sub-tasks never showed when it
    /// was due, and an overdue one never turned red. The date is dropped
    /// only when it is today, which the card's title already says.
    @ViewBuilder
    private func trailing(_ note: Note, tint: Color) -> some View {
        HStack(spacing: 6) {
            if let p = note.checklistProgress {
                let frac = Double(p.done) / Double(max(p.total, 1))
                HStack(spacing: 4) {
                    Text("\(p.done)/\(p.total)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                    Capsule()
                        .fill(tint.opacity(0.2))
                        .frame(width: 26, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: 26 * frac, height: 3)
                        }
                }
            }
            if let due = note.dueDate, !note.isDueToday(now: today) {
                Text(due, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(note.isOverdue(now: today) ? .red : .primary.opacity(0.5))
            }
        }
    }

    // MARK: Background + empty

    private var haloScale: Double { theme.mode == .light ? 0.4 : 1.0 }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CyberPalette.backdrop.opacity(0.92))
            // Corner glow — same pink/cyan signature as the iOS widget.
            // Softer in light, where full-strength glow tints the whole
            // card instead of lighting its corners (see CyberBackground).
            RadialGradient(colors: [CyberPalette.neonCyan.opacity(0.16 * haloScale), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 180)
            RadialGradient(colors: [CyberPalette.neonPink.opacity(0.12 * haloScale), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 160)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(CyberPalette.neonCyan)
            Text(L("All clear", "全部完成"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(L("Nothing pinned or due.", "暂无置顶或今日任务"))
                .font(.system(size: 10))
                .foregroundStyle(.primary.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}
