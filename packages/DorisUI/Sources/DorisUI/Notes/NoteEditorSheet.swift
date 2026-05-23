import SwiftUI
import SwiftData
import DorisCore

/// Cyber-themed full-editor for a single `Note`. Used as a sheet on both
/// macOS (MainWindowView, AnchorView dropdown) and iOS (NotesScreen). The
/// view binds directly to the `Note` via `@Bindable` so edits persist
/// through SwiftData's normal autosave path — no explicit save call
/// required, but `Done` updates `updatedAt` so the list re-sorts.
///
/// Buttons:
///   · **Done**     — bumps `updatedAt`, dismisses.
///   · **Delete**   — confirms, then deletes the model and dismisses.
///
/// Adaptive: dark theme = deep purple cyber backdrop, light = cream.
/// Pulls language from `LanguageSettings.shared` so the same editor reads
/// in EN or 中文 depending on the user's setting.
public struct NoteEditorSheet: View {
    @Bindable public var note: Note
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var confirmingDelete: Bool = false

    public init(note: Note) {
        self.note = note
    }

    public var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: - macOS — borderless cyber sheet (NavigationStack title bars on
    // mac sheets feel heavy; instead we draw our own header strip)

    #if os(macOS)
    private var macBody: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            Divider().overlay(Color.primary.opacity(0.08))
            editorBody
                .padding(18)
        }
        .frame(minWidth: 540, idealWidth: 620, minHeight: 420, idealHeight: 520)
        .background(CyberPalette.backdrop.ignoresSafeArea())
        .alert(
            L("Delete this note?", "删除这条笔记?"),
            isPresented: $confirmingDelete
        ) {
            Button(L("Delete", "删除"), role: .destructive) {
                note.archive()
                try? ctx.save()
                dismiss()
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("This can't be undone.", "此操作无法撤销。"))
        }
    }
    #endif

    // MARK: - iOS — NavigationStack with bar buttons

    #if !os(macOS)
    private var iosBody: some View {
        NavigationStack {
            ZStack {
                CyberBackground()
                editorBody
                    .padding(18)
            }
            .ignoresSafeArea()
            .navigationTitle(L("Edit", "编辑"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(CyberPalette.neonPink.opacity(0.9))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done", "完成")) {
                        note.touch()
                        try? ctx.save()
                        dismiss()
                    }
                    .foregroundStyle(CyberPalette.neonCyan)
                    .fontWeight(.semibold)
                }
            }
            .alert(
                L("Delete this note?", "删除这条笔记?"),
                isPresented: $confirmingDelete
            ) {
                Button(L("Delete", "删除"), role: .destructive) {
                    ctx.delete(note)
                    try? ctx.save()
                    dismiss()
                }
                Button(L("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(L("This can't be undone.", "此操作无法撤销。"))
            }
        }
    }
    #endif

    // MARK: - Shared header (mac only — iOS uses navigation bar)

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CyberPalette.neonPink)
            Text(L("Edit Note", "编辑笔记"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .kerning(0.5)
                .foregroundStyle(.primary)
            Spacer()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label(L("Delete", "删除"), systemImage: "trash")
                    .font(.caption)
                    .foregroundStyle(CyberPalette.neonPink.opacity(0.9))
            }
            .buttonStyle(.plain)
            Button {
                note.touch()
                try? ctx.save()
                dismiss()
            } label: {
                Text(L("Done", "完成"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(CyberPalette.neonCyan.opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke(CyberPalette.neonCyan.opacity(0.5), lineWidth: 0.6)
                    )
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - Done toggle binding

    /// Custom binding for the "Done" toggle. Couples `note.done` and
    /// `note.completedAt` so flipping the toggle also stamps when (or
    /// clears the stamp on un-complete). Also bumps `updatedAt` so the
    /// list re-sorts and CloudKit mirror picks up the change.
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

    // MARK: - Shared editor body

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                L("Title", "标题"),
                text: $note.title,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)

            // Attribute row — Pin · Checklist · Due · Done. The Due chip
            // is the same component the Mac InlineNoteEditor uses, so a
            // user can schedule from either editor with the same UX.
            HStack(spacing: 10) {
                Toggle(isOn: $note.pinned) {
                    Label(L("Pinned", "置顶"), systemImage: "pin.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(CyberPalette.neonPink)

                Toggle(isOn: $note.isChecklist) {
                    Label(L("Checklist", "清单"), systemImage: "checklist")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(CyberPalette.neonCyan)

                DueDateChipButton(note: note, compact: false)

                Toggle(isOn: doneBinding) {
                    Label(
                        L("Done", "已完成"),
                        systemImage: note.done ? "checkmark.seal.fill" : "checkmark.seal"
                    )
                    .font(.caption)
                }
                .toggleStyle(.button)
                .tint(CyberPalette.doneAccent)

                Spacer()
            }

            Text(note.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.45))

            Divider().overlay(Color.primary.opacity(0.08))

            // Content area — pinned to top and given .infinity height so
            // a short checklist no longer floats centred in the screen
            // with empty bands above and below. ScrollView ensures the
            // checklist scrolls if it ever exceeds the editor height.
            Group {
                if note.isChecklist {
                    ScrollView {
                        ChecklistEditorView(note: note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    TextEditor(text: $note.bodyMarkdown)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.primary.opacity(0.07), lineWidth: 0.5)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Anchor the whole editor to the top of its container — without
        // this, ZStack on iOS centres the VStack vertically and a short
        // checklist drifts into the middle of the screen with big blank
        // bands above and below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: note.bodyMarkdown) { _, _ in
            note.touch()
        }
        .onChange(of: note.title) { _, _ in
            note.touch()
        }
    }
}
