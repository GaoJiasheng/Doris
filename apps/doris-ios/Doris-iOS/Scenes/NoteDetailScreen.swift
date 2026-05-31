import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Pushed (NavigationLink) note editor — mirrors macOS `InlineNoteEditor`
/// but uses the iOS NavigationStack chrome (system back button, toolbar
/// trash) instead of a custom header strip.
///
/// Autosave: SwiftData @Bindable auto-persists on every keystroke; we
/// stamp `note.touch()` via `.onChange` so `updatedAt` stays current for
/// CloudKit sync disambiguation.
///
/// Features in this editor:
///   · Title + Pinned/Checklist/DueDate meta row
///   · Markdown body editor OR ChecklistEditorView
///   · Markdown preview toggle (toolbar book icon)
///   · Read-only tag chip row
///   · Due-date chip: tap → date picker sheet; color-coded by urgency
///   · Trash button → confirmation → soft-delete (archive)
struct NoteDetailScreen: View {
    @Bindable var note: Note
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var showingDatePicker = false
    @State private var showingMarkdownPreview = false

    var onDelete: () -> Void

    init(note: Note, onDelete: @escaping () -> Void = {}) {
        self.note = note
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Title
                TextField(
                    L("Title", "标题"),
                    text: $note.title,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1...3)

                metaRow

                // Tag chips (read-only)
                if let tags = note.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags) { tag in
                                TagChipView(name: tag.name, colorHex: tag.colorHex)
                            }
                        }
                    }
                }

                if note.isChecklist {
                    // Don't force a minimum height on the checklist —
                    // when the user has only a couple of items, the
                    // 240pt minimum left a big blank below the list
                    // that looked like a broken layout. The parent
                    // ScrollView handles overflow when the list grows.
                    ChecklistEditorView(note: note)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else if showingMarkdownPreview {
                    MarkdownText(note.bodyMarkdown)
                        .frame(minHeight: 320, alignment: .topLeading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.primary.opacity(0.07), lineWidth: 0.5)
                        )
                } else {
                    TextEditor(text: $note.bodyMarkdown)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 320)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.primary.opacity(0.07), lineWidth: 0.5)
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Prominent Complete toggle in the nav bar — the
            // Done switch in metaRow was too easy to miss next to
            // Pin / Checklist / Due. A standalone toolbar button
            // keeps the "I finished this" gesture one-tap accessible
            // and reuses the same `doneBinding` mutation path so
            // `completedAt` + `updatedAt` stay consistent.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    doneBinding.wrappedValue.toggle()
                    try? ctx.save()
                } label: {
                    Image(systemName: note.done
                          ? "checkmark.circle.fill"
                          : "checkmark.circle")
                        .foregroundStyle(note.done
                                         ? CyberPalette.doneAccent
                                         : .primary.opacity(0.65))
                }
                .accessibilityLabel(note.done
                                    ? L("Mark not done", "标为未完成")
                                    : L("Mark as done", "标为已完成"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Markdown preview toggle (only for non-checklist notes)
                if !note.isChecklist {
                    Button {
                        showingMarkdownPreview.toggle()
                    } label: {
                        Image(systemName: showingMarkdownPreview ? "book.fill" : "book")
                            .foregroundStyle(showingMarkdownPreview
                                             ? CyberPalette.neonCyan
                                             : .primary.opacity(0.6))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(CyberPalette.neonPink.opacity(0.9))
                }
            }
        }
        .alert(
            L("Delete this note?", "删除这条笔记?"),
            isPresented: $confirmingDelete
        ) {
            Button(L("Delete", "删除"), role: .destructive) {
                note.archive()
                try? ctx.save()
                onDelete()
                dismiss()
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("The note will be moved to Recently Deleted.",
                   "笔记将移至最近删除。"))
        }
        .sheet(isPresented: $showingDatePicker) {
            dueDatePickerSheet
        }
        .onChange(of: note.bodyMarkdown) { _, _ in note.touch() }
        .onChange(of: note.title)        { _, _ in note.touch() }
    }

    // MARK: - Meta row

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(isOn: $note.pinned) {
                    Label(L("Pinned", "置顶"), systemImage: "pin.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(CyberPalette.neonPink)
                .controlSize(.small)
                .onChange(of: note.pinned) { _, _ in note.touch() }

                Toggle(isOn: $note.isChecklist) {
                    Label(L("Checklist", "清单"), systemImage: "checklist")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(CyberPalette.neonCyan)
                .controlSize(.small)
                .onChange(of: note.isChecklist) { _, _ in note.touch() }

                // Due date chip
                Button {
                    showingDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        if let due = note.dueDate {
                            Text(due, format: .dateTime.month(.abbreviated).day())
                                .font(.caption.monospacedDigit())
                        } else {
                            Text(L("Due", "截止"))
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(dueDateColor.opacity(0.15)))
                    .overlay(Capsule().stroke(dueDateColor.opacity(0.45), lineWidth: 0.6))
                    .foregroundStyle(note.dueDate == nil ? .primary.opacity(0.5) : dueDateColor)
                }
                .buttonStyle(.plain)

                // Mark-whole-note-as-done toggle. Same recipe as the
                // editor sheets — sets `completedAt` so Today-tab
                // completed-state visuals (strikethrough, DONE pill,
                // dimmed card) light up immediately on save.
                Toggle(isOn: doneBinding) {
                    Label(
                        L("Done", "已完成"),
                        systemImage: note.done ? "checkmark.seal.fill" : "checkmark.seal"
                    )
                    .font(.caption)
                }
                .toggleStyle(.button)
                .tint(CyberPalette.doneAccent)
                .controlSize(.small)

                Spacer()
            }

            Text(note.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.45))
                .monospacedDigit()
        }
    }

    /// Mirror of the binding in `NoteEditorSheet` / `InlineNoteEditor` —
    /// flipping the Done toggle also stamps (or clears) `completedAt`
    /// so the Today tab's completed-card visuals key off a real value
    /// instead of inferring from `done` alone.
    private var doneBinding: Binding<Bool> {
        Binding(
            get: { note.done },
            set: { newValue in
                note.done = newValue
                note.completedAt = newValue ? Date() : nil
                note.touch()
            }
        )
    }

    private var dueDateColor: Color {
        guard let due = note.dueDate else { return CyberPalette.neonCyan }
        let cal = Calendar.current
        if due < Date() { return .red }
        if cal.isDateInToday(due) { return .yellow }
        return CyberPalette.neonCyan
    }

    // MARK: - Due date picker sheet

    private var dueDatePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    L("Due date", "截止日期"),
                    selection: Binding(
                        get: { note.dueDate ?? Date() },
                        set: { note.dueDate = $0; note.touch() }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(CyberPalette.neonCyan)

                if note.dueDate != nil {
                    Button(role: .destructive) {
                        note.dueDate = nil
                        note.touch()
                        showingDatePicker = false
                    } label: {
                        Label(L("Clear due date", "清除截止日期"),
                              systemImage: "xmark.circle")
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
                    Button(L("Done", "完成")) {
                        showingDatePicker = false
                    }
                    .foregroundStyle(CyberPalette.neonCyan)
                }
            }
            .background { CyberBackground().ignoresSafeArea() }
        }
        .presentationDetents([.medium])
    }
}
