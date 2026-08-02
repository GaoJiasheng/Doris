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
        // Excludes trashed rows too — `deleted` is a soft-delete flag, so
        // without it the Trash's contents stay listed here.
        filter: #Predicate<Note> { note in !note.archived && !note.deleted },
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
    /// Drives keyboard dismissal: bind to the bottom search TextField so
    /// we can pop the keyboard via the `.toolbar(.keyboard)` "Done"
    /// button without relying on the user finding the Search key on the
    /// IME (which on Chinese keyboards is huge but on English defaults
    /// to "return", confusing the affordance).
    @FocusState private var searchFocused: Bool
    // Drives the "synced X ago" label. 60s cadence → minute granularity,
    // not a per-second stopwatch.
    private let tickTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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
                        noteListRow(for: n)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Native iOS pattern: drag the list down → keyboard
            // dismisses interactively. Pairs with the keyboard-toolbar
            // Done button below so users have two ways out: gesture OR
            // explicit tap.
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await runSync() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Keyboard accessory: a single "完成" button on the
                // trailing side that pops focus. Critical on Chinese
                // IMEs where the keyboard's green "搜索" key reads as
                // another submit, not a dismissal.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Done", "完成")) {
                        searchFocused = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(CyberPalette.neonCyan)
                }
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
            // Note detail destination.
            //
            // Resolved by `NoteDetailHost`, NOT by reaching into `notes` here.
            // This closure re-runs whenever the @Query publishes — and the
            // query is sorted by `updatedAt`, so editing the very note being
            // shown re-emits it. Reading `notes` here coupled the open editor
            // to that churn, rebuilding its text fields mid-edit and breaking
            // marked-text (Pinyin) input. The host holds the note itself, so
            // list re-sorting no longer reaches the editor.
            .navigationDestination(for: UUID.self) { id in
                NoteDetailHost(id: id) {
                    if !path.isEmpty { path.removeLast() }
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

    // MARK: - Bulk archive (done items)

    /// Count of notes that are completed but not yet archived. Drives
    /// the "归档已完成 (N)" chip in the status bar: chip only appears
    /// when there's something to archive, matching macOS behaviour.
    private var doneActiveCount: Int {
        notes.filter { !$0.archived && $0.done }.count
    }

    /// Bulk-archive every active+done note in one pass. Morning-routine
    /// shortcut: yesterday's finished items vanish with one tap;
    /// undone ones stay rolled over to today.
    private func archiveAllDone() {
        let now = Date()
        for n in notes where !n.archived && n.done {
            n.archived = true
            n.archivedAt = now
            n.updatedAt = now
        }
        try? ctx.save()
    }

    private func runSync() async {
        AppCommands.syncNow()
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    // MARK: - List row (extracted so the body's type-checker doesn't
    //              choke on the nested ForEach + swipe + contextMenu)

    @ViewBuilder
    private func noteListRow(for n: Note) -> some View {
        NavigationLink(value: n.id) {
            NoteRow(note: n)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
        // Trailing (left-swipe) → toggle completed. Archive moved into
        // the long-press menu where it belongs (destructive-red on
        // common swipe read wrong for "I'm done with this").
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
            // Focus (pomodoro) → opens the full-screen dial.
            if FocusTimer.shared.isFocused(noteID: n.id) {
                Button {
                    FocusTimer.shared.stop()
                } label: {
                    Label(L("Stop focus", "停止专注"), systemImage: "stop.circle")
                }
            } else {
                Menu {
                    ForEach([15, 25, 45], id: \.self) { m in
                        Button(L("\(m) min", "\(m) 分钟")) {
                            FocusTimer.shared.start(
                                noteID: n.id, title: n.title, subtask: nil, minutes: m
                            )
                        }
                    }
                } label: {
                    Label(L("Start focus", "开始专注"), systemImage: "timer")
                }
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
            // Bind to @FocusState so the keyboard toolbar Done button +
            // submit gesture can pop the keyboard. Without this hook
            // the field doesn't surrender focus and the keyboard stays
            // up forever (no tap-outside-to-dismiss for custom fields).
            .focused($searchFocused)
            .onSubmit { searchFocused = false }
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

            // Right: archive-done button (shown only when there's at
            // least one completed-but-not-yet-archived note) followed
            // by the always-on Archived link.
            if doneActiveCount > 0 {
                Button { archiveAllDone() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L("Archive done (\(doneActiveCount))",
                               "归档已完成 (\(doneActiveCount))"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CyberPalette.doneAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(CyberPalette.doneAccent.opacity(0.10))
                    )
                    .overlay(
                        Capsule().stroke(CyberPalette.doneAccent.opacity(0.45), lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }

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
        // Minute granularity — no seconds stopwatch. Under a minute reads
        // "just now"; past that, RelativeDateTimeFormatter shows min/hr/day.
        if Date().timeIntervalSince(last) < 60 {
            return L("Synced · just now", "已同步 · 刚刚")
        }
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
        // Exclude trashed entries — see SettingsView.MacRecentlyDeletedTab
        // for the rationale. After "Delete All" the row is set to
        // `deleted = true` (soft-delete) so it survives sync race; the
        // archived sheet should treat it as gone immediately.
        filter: #Predicate<Note> { note in note.archived && !note.deleted },
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
                                    // Soft-delete instead of ctx.delete so
                                    // CloudKit mirror doesn't resurrect
                                    // the row from another device's local
                                    // copy. SyncTimer.purgeTombstones
                                    // hard-deletes 24h after deletedAt.
                                    let now = Date()
                                    note.deleted = true
                                    note.deletedAt = now
                                    note.updatedAt = now
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
                            // Soft-delete; see equivalent comment in
                            // SettingsView.swift (Mac) for the CloudKit
                            // race rationale. Items disappear from this
                            // view immediately because the @Query for
                            // `archived` excludes `deleted=true`.
                            let now = Date()
                            for n in archived {
                                n.deleted = true
                                n.deletedAt = now
                                n.updatedAt = now
                            }
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

    /// Delegate to the shared model-level computed property so every
    /// surface (Today pinned/calendar, Notes list, calendar timeline)
    /// reads "completed" from the same source of truth.
    private var isCompleted: Bool { note.isCompleted }

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
                    // Cleaner rows: no running relative timer here — the
                    // creation time lives in the detail page. Only show the
                    // DONE pill (completed) or the due-date chip, and only
                    // when there's actually one to show.
                    if isCompleted {
                        HStack(spacing: 6) { donePill }
                    } else if let due = note.dueDate {
                        HStack(spacing: 6) { dueDateChip(due) }
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
