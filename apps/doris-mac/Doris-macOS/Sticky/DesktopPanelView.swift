import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Always-on-desktop dashboard: a compact list of pinned (置顶 + 长期)
/// and today/overdue (日程) tasks, with inline done toggles. Live via
/// @Query so it tracks edits made anywhere in the app. Hosted in a
/// floating StickyPanel by DesktopPanelController.
///
/// Visual language is kept in lock-step with the iOS Tasks widget:
/// adaptive cyber gradient + corner glow, per-section accent rails
/// (pink 置顶 / violet 长期 / cyan 日程), checklist progress pills with a
/// fill bar, overdue-red due dates, a count chip in the header.
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
    /// Inline controls strip (opacity + always-on-top) toggled from the
    /// header. Inline rather than a popover: popovers on a non-activating
    /// panel are unreliable, and an inline strip can host a live slider.
    @State private var showControls = false

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

    private var todayNotes: [Note] {
        allNotes
            .filter { !$0.pinned && $0.dueDate != nil && !$0.isPastAndCompleted() }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private func pinnedOrder(_ a: Note, _ b: Note) -> Bool {
        if a.order != b.order { return a.order < b.order }
        return a.updatedAt > b.updatedAt
    }

    private var total: Int { regularPinned.count + longTermNotes.count + todayNotes.count }

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
        // Only the background + edge fade with the opacity slider; the
        // content (tasks, controls) stays fully opaque so a see-through
        // panel is still readable and the slider never fades itself out.
        .background(panelBackground.opacity(panelSettings.opacity))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CyberPalette.dimPanelStroke, lineWidth: 0.9)
                .opacity(panelSettings.opacity)
        )
        .preferredColorScheme(theme.mode.colorScheme)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if showControls { controlsStrip }
            Divider().overlay(Color.primary.opacity(0.08))

            if total == 0 {
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
                        if !todayNotes.isEmpty {
                            section(L("Upcoming", "日程"), icon: "calendar",
                                    tint: CyberPalette.neonCyan, notes: todayNotes)
                        }
                    }
                }
            }
        }
        .padding(12)
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
            .help(L("Open main window", "打开主窗口"))
            Spacer()
            Text(Date().formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.5))
            if total > 0 {
                Text("\(total)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(CyberPalette.neonCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(CyberPalette.neonCyan.opacity(0.16)))
            }
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showControls.toggle() }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(showControls ? CyberPalette.neonCyan
                                                  : CyberPalette.neonCyan.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help(L("Panel options", "面板选项"))
            Button { AppCommands.openMainWindow() } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CyberPalette.neonCyan.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help(L("Open main window", "打开主窗口"))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(L("Hide desktop panel", "隐藏桌面面板"))
        }
    }

    // MARK: Controls (opacity + always-on-top)

    private var controlsStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: Binding(
                get: { panelSettings.alwaysOnTop },
                set: { on in
                    panelSettings.alwaysOnTop = on   // persist
                    onAlwaysOnTopChanged(on)         // apply to the window live
                }
            )) {
                Label(L("Always on top", "总在最前"), systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(CyberPalette.neonPink)

            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: $panelSettings.opacity,
                       in: DesktopPanelSettings.minOpacity...1.0)
                    .controlSize(.mini)
                    .tint(CyberPalette.neonCyan)
                Text("\(Int((panelSettings.opacity * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
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

    @ViewBuilder
    private func trailing(_ note: Note, tint: Color) -> some View {
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
        } else if let due = note.dueDate {
            Text(due, format: .dateTime.month(.twoDigits).day(.twoDigits))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(due < Date() && !note.isCompleted ? .red : .primary.opacity(0.5))
        }
    }

    // MARK: Background + empty

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CyberPalette.backdrop.opacity(0.92))
            // Corner glow — same pink/cyan signature as the iOS widget.
            RadialGradient(colors: [CyberPalette.neonCyan.opacity(0.16), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 180)
            RadialGradient(colors: [CyberPalette.neonPink.opacity(0.12), .clear],
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
