import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Always-on-desktop dashboard: a compact list of pinned (置顶 + 长期)
/// and today/overdue tasks, with inline done toggles. Live via @Query
/// so it tracks edits made anywhere in the app. Hosted in a floating
/// StickyPanel by DesktopPanelController.
struct DesktopPanelView: View {
    let onClose: () -> Void
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var theme = ThemeSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared

    @Query(
        filter: #Predicate<Note> { !$0.archived && !$0.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var allNotes: [Note]

    private var pinnedNotes: [Note] {
        allNotes.filter { $0.pinned }.sorted { a, b in
            if a.longTerm != b.longTerm { return !a.longTerm && b.longTerm }  // 置顶 before 长期
            if a.order != b.order { return a.order < b.order }
            return a.updatedAt > b.updatedAt
        }
    }

    private var todayNotes: [Note] {
        allNotes
            .filter { !$0.pinned && $0.dueDate != nil && !$0.isPastAndCompleted() }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CyberPalette.neonCyan)
                Text(L("Doris · Today", "Doris · 今日"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text(Date().formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.5))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(L("Hide desktop panel", "隐藏桌面面板"))
            }

            Divider().overlay(Color.primary.opacity(0.08))

            if pinnedNotes.isEmpty && todayNotes.isEmpty {
                Text(L("Nothing pinned or due.", "暂无置顶或今日任务。"))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !pinnedNotes.isEmpty {
                            sectionLabel(L("Pinned", "置顶"), tint: CyberPalette.neonPink)
                            ForEach(pinnedNotes) { row($0) }
                        }
                        if !todayNotes.isEmpty {
                            sectionLabel(L("Upcoming", "日程"), tint: CyberPalette.neonCyan)
                            ForEach(todayNotes) { row($0) }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CyberPalette.backdrop.opacity(0.92))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CyberPalette.neonCyan.opacity(0.22), lineWidth: 0.8)
        )
        .preferredColorScheme(theme.mode.colorScheme)
    }

    private func sectionLabel(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(1.5)
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func row(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Button {
                let now = Date()
                note.done.toggle()
                note.completedAt = note.done ? now : nil
                note.updatedAt = now
                try? ctx.save()
            } label: {
                Image(systemName: note.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(note.isCompleted
                                     ? AnyShapeStyle(CyberPalette.doneAccent)
                                     : AnyShapeStyle(Color.primary.opacity(0.5)))
            }
            .buttonStyle(.plain)

            Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                .font(.system(size: 12))
                .strikethrough(note.isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                .foregroundStyle(note.isCompleted
                    ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.45))
                    : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .lineLimit(1)

            Spacer(minLength: 0)

            if let p = note.checklistProgress {
                Text("\(p.done)/\(p.total)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.5))
            } else if let due = note.dueDate {
                Text(due, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(due < Date() && !note.isCompleted ? .red : .primary.opacity(0.5))
            }
        }
    }
}
