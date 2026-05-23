import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// iOS Notes screen — mirrors Mac's MainNotesList flow:
///   · `@Query` of non-archived Notes sorted pinned-first then by `updatedAt desc`
///   · CyberCard rows with icon + title + body excerpt + relative time
///   · Tap → push `NoteDetailScreen` (NavigationLink)
///   · "+" creates and pushes immediately
///   · Swipe-to-delete (trailing) → soft-archive
///   · Leading swipe → toggle pin
///   · Long-press contextMenu → Pin/Unpin · Archive · Set Due Date
///   · Pull-to-refresh → `AppCommands.syncNow`
///   · `.searchable` filters on title + body
///   · Sync pill (top) turns red on error; calendar button pushes TodayScreen
struct NotesScreen: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var sync = SyncSettings.shared
    @ObservedObject private var theme = ThemeSettings.shared
    @Environment(\.modelContext) private var ctx

    @Query(
        filter: #Predicate<Note> { note in !note.archived },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var notes: [Note]

    /// Pin-first ordering: SwiftData's @Query can't sort by Bool keyPaths,
    /// so we sort client-side (pinned notes first, then by updatedAt desc).
    private var sortedNotes: [Note] {
        notes.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }

    @State private var path = NavigationPath()
    @State private var showArchived = false
    @State private var nowTick: Date = Date()
    @State private var searchText: String = ""
    @State private var dueDateNoteID: UUID?
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return sortedNotes }
        let q = searchText.lowercased()
        return sortedNotes.filter {
            $0.title.lowercased().contains(q) ||
            $0.bodyMarkdown.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if filteredNotes.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredNotes) { n in
                        NavigationLink(value: n.id) {
                            NoteRow(note: n)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                        // Trailing (left-swipe) → toggle completed. Used
                        // to be Archive, but completing is a far more
                        // frequent action and the destructive red read
                        // wrong for "I'm done with this." Archive moved
                        // into the long-press menu where it belongs.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                n.done.toggle()
                                n.completedAt = n.done ? Date() : nil
                                n.touch()
                                try? ctx.save()
                            } label: {
                                Label(
                                    n.done ? L("Undo", "取消完成") : L("Done", "完成"),
                                    systemImage: n.done ? "arrow.uturn.backward" : "checkmark.circle.fill"
                                )
                            }
                            .tint(CyberPalette.doneAccent)
                        }
                        // Leading (right-swipe): toggle pin
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                n.pinned.toggle()
                                n.touch()
                                try? ctx.save()
                            } label: {
                                Label(
                                    n.pinned ? L("Unpin", "取消置顶") : L("Pin", "置顶"),
                                    systemImage: n.pinned ? "pin.slash" : "pin"
                                )
                            }
                            .tint(CyberPalette.neonPink)
                        }
                        // Long-press context menu — full action set lives
                        // here. Archive is now ONLY reachable through
                        // long-press so casual left-swipes can't soft-
                        // delete a note by accident.
                        .contextMenu {
                            Button {
                                n.pinned.toggle()
                                n.touch()
                                try? ctx.save()
                            } label: {
                                Label(
                                    n.pinned ? L("Unpin", "取消置顶") : L("Pin", "置顶"),
                                    systemImage: n.pinned ? "pin.slash" : "pin.fill"
                                )
                            }
                            Button {
                                n.done.toggle()
                                n.completedAt = n.done ? Date() : nil
                                n.touch()
                                try? ctx.save()
                            } label: {
                                Label(
                                    n.done ? L("Mark as undone", "标为未完成") : L("Mark as done", "标为已完成"),
                                    systemImage: n.done ? "circle" : "checkmark.circle.fill"
                                )
                            }
                            Button {
                                dueDateNoteID = n.id
                            } label: {
                                Label(L("Set due date", "设置截止日期"), systemImage: "calendar")
                            }
                            Divider()
                            Button(role: .destructive) {
                                n.archive()
                                try? ctx.save()
                            } label: {
                                Label(L("Archive", "归档"), systemImage: "archivebox")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await runSync() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("DORIS")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .kerning(2.5)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [CyberPalette.neonPink, CyberPalette.neonCyan],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        Text(L("cyber notes", "赛博笔记"))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(CyberPalette.neonCyan.opacity(0.7))
                            .kerning(1.5)
                    }
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    ThemeToggleButton()
                    NavigationLink(value: "calendar") {
                        Image(systemName: "calendar")
                            .foregroundStyle(CyberPalette.neonCyan.opacity(0.85))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let n = Note(title: "")
                        ctx.insert(n)
                        try? ctx.save()
                        path.append(n.id)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(CyberPalette.neonPink)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                statusBar
            }
            // Search bar lives at the bottom now — the top of the screen
            // reads cleaner with just the title + sync pill, and a
            // thumb-reachable search field is easier to use one-handed.
            // No `.ignoresSafeArea(.keyboard)` here on purpose — we want
            // the inset to lift with the keyboard so the field stays
            // visible while typing.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                searchBar
            }
            // Note detail destination
            .navigationDestination(for: UUID.self) { id in
                if let note = notes.first(where: { $0.id == id }) {
                    NoteDetailScreen(note: note) {
                        if !path.isEmpty { path.removeLast() }
                    }
                } else {
                    Text(L("Note not found", "笔记不存在"))
                        .foregroundStyle(.secondary)
                }
            }
            // Calendar timeline destination
            .navigationDestination(for: String.self) { dest in
                if dest == "calendar" {
                    CalendarTimelineScreen()
                }
            }
            .sheet(isPresented: $showArchived) {
                ArchivedNotesSheet()
                    .preferredColorScheme(theme.mode.colorScheme)
            }
            // Quick due-date picker from contextMenu
            .sheet(item: Binding(
                get: { dueDateNoteID.flatMap { id in notes.first { $0.id == id } } },
                set: { if $0 == nil { dueDateNoteID = nil } }
            )) { note in
                quickDueDateSheet(note: note)
            }
            .onReceive(tickTimer) { nowTick = $0 }
        }
    }

    private func runSync() async {
        AppCommands.syncNow()
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    // MARK: - Quick due-date sheet (from contextMenu)

    private func quickDueDateSheet(note: Note) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    L("Due date", "截止日期"),
                    selection: Binding(
                        get: { note.dueDate ?? Date() },
                        set: { note.dueDate = $0; note.touch(); try? ctx.save() }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(CyberPalette.neonCyan)

                if note.dueDate != nil {
                    Button(role: .destructive) {
                        note.dueDate = nil
                        note.touch()
                        try? ctx.save()
                        dueDateNoteID = nil
                    } label: {
                        Label(L("Clear due date", "清除截止日期"), systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle(L("Set due date", "设置截止日期"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done", "完成")) { dueDateNoteID = nil }
                        .foregroundStyle(CyberPalette.neonCyan)
                }
            }
            .background { CyberBackground().ignoresSafeArea() }
        }
        .preferredColorScheme(theme.mode.colorScheme)
        .presentationDetents([.medium])
    }

    // MARK: - Bottom search bar
    //
    // Replaces the system `.searchable` (which docks at the top under
    // the title bar). A custom field at the bottom is easier to thumb-
    // reach and keeps the top of the list clean. The capsule shape +
    // neonCyan stroke ties into the rest of the cyber UI; the clear
    // button only renders when there's text to clear so the bar reads
    // empty by default.

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CyberPalette.neonCyan.opacity(0.7))
            TextField(
                L("Search notes…", "搜索笔记…"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CyberPalette.neonCyan.opacity(0.22), lineWidth: 0.7)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            // Subtle gradient fade so the search bar visually anchors to
            // the bottom edge instead of floating. ultraThinMaterial on
            // top of the system background to soften list rows scrolling
            // beneath.
            LinearGradient(
                colors: [Color.clear, .black.opacity(0.04), .black.opacity(0.08)],
                startPoint: .top, endPoint: .bottom
            )
            .background(.ultraThinMaterial.opacity(0.6))
        )
    }

    // MARK: - Compact status bar

    private var statusBar: some View {
        let hasError = sync.lastSyncError != nil
        let accentColor: Color = hasError ? .red : CyberPalette.neonCyan

        return HStack(spacing: 0) {
            // Left: sync button + status text. On error, retry the sync —
            // the full error detail and iCloud toggles live in the Settings
            // tab now, just a tap away on the tab bar.
            Button {
                AppCommands.syncNow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: hasError
                          ? "exclamationmark.icloud.fill"
                          : (sync.cloudKitEnabled ? "arrow.triangle.2.circlepath" : "icloud.slash"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                    Text(syncStatusLabel)
                        .font(.system(size: 11, design: .monospaced).monospacedDigit())
                        .foregroundStyle(hasError ? .red : .primary.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            // Right: archived notes button
            Button { showArchived = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L("Archived", "已归档"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(.primary.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(.primary.opacity(0.09), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.7))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private var syncStatusLabel: String {
        if let err = sync.lastSyncError {
            return err.count > 36 ? String(err.prefix(36)) + "…" : err
        }
        guard sync.cloudKitEnabled else { return L("Local only", "仅本地") }
        guard let last = sync.lastSyncedAt else { return L("Never synced", "尚未同步") }
        _ = nowTick
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return L("Synced ", "已同步 ") + f.localizedString(for: last, relativeTo: Date())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.primary.opacity(0.4))
            Text(searchText.isEmpty
                 ? L("No notes yet", "暂无笔记")
                 : L("No results", "无搜索结果"))
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.65))
            if searchText.isEmpty {
                Text(L("Tap + to create one. Pull down to sync.",
                       "点击 + 新建一条。下拉同步。"))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Archived notes sheet

private struct ArchivedNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Query(
        filter: #Predicate<Note> { note in note.archived },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var archived: [Note]

    var body: some View {
        NavigationStack {
            Group {
                if archived.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 36))
                            .foregroundStyle(.primary.opacity(0.3))
                        Text(L("No archived notes", "没有已归档的笔记"))
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(archived) { note in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(note.updatedAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L("Restore", "恢复")) {
                                    note.archived = false
                                    note.touch()
                                    try? ctx.save()
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(CyberPalette.neonCyan)
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.primary.opacity(0.04))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    ctx.delete(note)
                                    try? ctx.save()
                                } label: {
                                    Label(L("Delete", "删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background { CyberBackground().ignoresSafeArea() }
            .navigationTitle(L("Archived", "已归档"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done", "完成")) { dismiss() }
                        .foregroundStyle(CyberPalette.neonCyan)
                }
                if !archived.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive) {
                            for n in archived { ctx.delete(n) }
                            try? ctx.save()
                        } label: {
                            Text(L("Delete All", "全部删除"))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct NoteRow: View {
    let note: Note

    /// Treat the row as completed if either the note's own done flag is
    /// set OR it's a checklist whose items are all checked. Matches the
    /// `isCompleted` logic in TodayPinnedCard/Row so the entire app
    /// agrees on what "done" looks like.
    private var isCompleted: Bool {
        if note.done { return true }
        if note.isChecklist {
            let items = note.checklistItems ?? []
            return !items.isEmpty && items.allSatisfy(\.done)
        }
        return false
    }

    var body: some View {
        CyberCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.isChecklist ? "checklist" : "note.text")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        isCompleted
                            ? CyberPalette.doneAccent
                            : CyberPalette.neonPink.opacity(0.85)
                    )
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if note.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(CyberPalette.neonCyan)
                        }
                        Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                            .foregroundStyle(isCompleted
                                ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.45))
                                : AnyShapeStyle(HierarchicalShapeStyle.primary))
                            .lineLimit(1)
                    }
                    if let p = note.checklistProgress {
                        Text("\(p.done) / \(p.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary.opacity(0.55))
                    } else if !note.bodyMarkdown.isEmpty {
                        Text(note.bodyMarkdown)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.55))
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(note.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.primary.opacity(0.4))
                        // When completed, replace the due-date chip with
                        // a "DONE" pill so completion is the dominant
                        // signal on the row's meta line.
                        if isCompleted {
                            donePill
                        } else if let due = note.dueDate {
                            dueDateChip(due)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .opacity(isCompleted ? 0.72 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isCompleted)
    }

    private var donePill: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
            Text(L("DONE", "已完成"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
        }
        .foregroundStyle(CyberPalette.doneAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(
            Capsule(style: .continuous)
                .fill(CyberPalette.doneAccent.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CyberPalette.doneAccent.opacity(0.55), lineWidth: 0.7)
        )
    }

    private func dueDateChip(_ due: Date) -> some View {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let color: Color = due < startOfToday ? .red : cal.isDateInToday(due) ? .yellow : CyberPalette.neonCyan
        return HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 8))
            Text(due, format: .dateTime.month(.abbreviated).day())
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}
