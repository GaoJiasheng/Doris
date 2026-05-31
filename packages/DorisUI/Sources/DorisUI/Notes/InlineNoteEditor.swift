import SwiftUI
import SwiftData
import DorisCore

/// In-place note editor — drops into whatever container the host
/// provides (a column in the main window's split view, the dropdown
/// panel's tab body). Unlike `NoteEditorSheet` it does NOT wrap itself
/// in a sheet / NavigationStack / fixed-frame VStack — it's just a
/// compact toolbar + the editor surface, sized to fill its host.
///
/// Layout priority: text editing area is the hero. The toolbar
/// (Back / Pin / Checklist / Delete) is one tight row at the top so the
/// editor body gets every spare pixel of vertical space.
public struct InlineNoteEditor: View {
    @Bindable public var note: Note
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var confirmingDelete: Bool = false

    /// Called when the user wants to leave editing — Back button, Esc
    /// key, or after a successful Delete.
    public var onClose: () -> Void

    public init(note: Note, onClose: @escaping () -> Void) {
        self.note = note
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Minimal top toolbar: just navigation + destructive actions.
            // Behavior toggles (Pin / Checklist / Due / Done) moved into
            // a dedicated row under the title — mirrors the iOS editor
            // sheet layout, gives the toggles room to breathe with full
            // labels, and stops the title from feeling pinched against
            // a busy header.
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Title — large, looks like a page title rather than a form
            // field. The "Untitled" placeholder reads as such because
            // we don't render any background / border.
            TextField(
                L("Title", "标题"),
                text: $note.title,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.horizontal, 14)

            // Behaviour row: Pin · Checklist · Due · Done. Same visual
            // language as the iOS NoteEditorSheet's toggle row — capsule
            // buttons with state-tinted fill, full bilingual labels, the
            // updated-at relative time on the right.
            attributeRow
                .padding(.horizontal, 14)

            // Body editor (or checklist) — fills every remaining pixel.
            // The whole point of the redesign was to maximise this
            // surface area so writing actually feels comfortable.
            Group {
                if note.isChecklist {
                    ScrollView {
                        ChecklistEditorView(note: note)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    TextEditor(text: $note.bodyMarkdown)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Stamp updatedAt as the user types. SwiftData persists
        // automatically; we set it explicitly to drive list re-sort.
        .onChange(of: note.bodyMarkdown) { _, _ in note.touch() }
        .onChange(of: note.title)        { _, _ in note.touch() }
        .alert(
            L("Delete this note?", "删除这条笔记?"),
            isPresented: $confirmingDelete
        ) {
            Button(L("Delete", "删除"), role: .destructive) {
                note.archive()
                try? ctx.save()
                onClose()
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("The note will be archived and can be recovered from Settings.", "笔记将被归档，可以从设置中恢复。"))
        }
    }

    /// Minimal top bar — Back · Spacer · time · Delete. Behaviour
    /// toggles (Pin / Checklist / Due / Done) live in `attributeRow`
    /// under the title to mirror the iOS editor sheet's layout.
    private var topBar: some View {
        HStack(spacing: 6) {
            // Back
            Button {
                note.touch()
                try? ctx.save()
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help(L("Back to list", "返回列表"))

            Spacer(minLength: 0)

            // Prominent Complete button — the attribute row below has
            // a Done toggle too, but it's one of four small chips that
            // users were missing. A solid pill in the top bar makes
            // "I finished this" a single, obvious click.
            Button {
                let now = Date()
                note.done.toggle()
                note.completedAt = note.done ? now : nil
                note.updatedAt = now
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: note.done
                          ? "checkmark.circle.fill"
                          : "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(note.done ? L("Done", "已完成") : L("Complete", "完成"))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(note.done
                                 ? CyberPalette.doneAccent
                                 : Color.primary.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(note.done
                                   ? CyberPalette.doneAccent.opacity(0.12)
                                   : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(note.done
                                     ? CyberPalette.doneAccent.opacity(0.5)
                                     : Color.primary.opacity(0.18),
                                     lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .help(note.done
                  ? L("Mark as not done", "标为未完成")
                  : L("Mark as done", "标为已完成"))

            Text(RelativeTime.short(note.updatedAt))
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.45))
                .help(absoluteTimeText)

            // Delete
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CyberPalette.neonPink.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(CyberPalette.neonPink.opacity(0.08))
                    )
                    .overlay(
                        Capsule().stroke(CyberPalette.neonPink.opacity(0.25), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help(L("Delete this note", "删除这条笔记"))
        }
    }

    /// Attribute row — Pin · Checklist · Due · Done. Sits between title
    /// and body so the user can scan & toggle a note's full state in
    /// one row, exactly like the iOS NoteEditorSheet.
    private var attributeRow: some View {
        HStack(spacing: 10) {
            pinToggle
            checklistToggle
            DueDateChipButton(note: note, compact: false)
            doneToggle
            Spacer(minLength: 0)
        }
    }

    /// Toggle the whole note as completed. Mirrors `doneBinding` from
    /// NoteEditorSheet — also stamps `completedAt` so the Today tab's
    /// completed-state visuals (and any future "completed at" sort)
    /// have the timestamp they need. Uses the same system Toggle +
    /// `.toggleStyle(.button)` recipe as pinToggle/checklistToggle so
    /// the pressed-state fill is identical to iOS.
    private var doneToggle: some View {
        Toggle(isOn: doneBinding) {
            Label(
                L("Done", "已完成"),
                systemImage: note.done ? "checkmark.seal.fill" : "checkmark.seal"
            )
            .font(.caption)
        }
        .toggleStyle(.button)
        .tint(CyberPalette.doneAccent)
        .help(note.done
              ? L("Mark as not done", "标为未完成")
              : L("Mark as done", "标为已完成"))
    }

    /// Custom binding that stamps `completedAt` whenever the toggle
    /// flips, matching the per-checkbox semantics in TodoRow.
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

    /// Pin toggle — system `Toggle(.button)` style matches iOS exactly:
    /// when ON the capsule fills with the tint color, when OFF it sits
    /// as a subtle outlined pill. Earlier iteration hand-drew this with
    /// only an icon-color change on press, which read as too quiet next
    /// to the iOS sheet.
    private var pinToggle: some View {
        Toggle(isOn: $note.pinned) {
            Label(L("Pinned", "置顶"), systemImage: "pin.fill")
                .font(.caption)
        }
        .toggleStyle(.button)
        .tint(CyberPalette.neonPink)
        .help(note.pinned
              ? L("Unpin from top", "取消置顶")
              : L("Pin to top of list", "置顶到列表顶部"))
    }

    /// Checklist toggle — same `Toggle(.button)` recipe as `pinToggle`.
    /// On enable, prepend `- [ ] ` to every non-empty body line that
    /// isn't already a checkbox — the body field is the SINGLE source
    /// of truth for both modes (no separate `checklistItems` storage),
    /// so flipping the toggle ON should visually transform the user's
    /// existing lines into tasks. Disable doesn't strip the markers
    /// (they're still readable plain text).
    private var checklistToggle: some View {
        Toggle(isOn: checklistBinding) {
            Label(L("Checklist", "清单"), systemImage: "checklist")
                .font(.caption)
        }
        .toggleStyle(.button)
        .tint(CyberPalette.neonCyan)
        .help(note.isChecklist
              ? L("Plain note", "纯文本")
              : L("Convert to checklist", "转为清单"))
    }

    /// Drives the checklist toggle. Switching ON also injects checkbox
    /// markers into the body so existing lines turn into tasks; we keep
    /// that conversion centralised here so the Toggle wrapper stays
    /// declarative.
    private var checklistBinding: Binding<Bool> {
        Binding(
            get: { note.isChecklist },
            set: { newValue in
                if newValue && !note.isChecklist {
                    convertBodyToChecklistMarkers()
                }
                note.isChecklist = newValue
                note.touch()
            }
        )
    }

    /// Prepend `- [ ] ` to every non-empty body line that isn't already
    /// a checkbox. Called when the user flips the checklist toggle ON
    /// so their existing lines visually become tasks. Idempotent — a
    /// line that already starts with `- [ ]` or `- [x]` is left alone.
    private func convertBodyToChecklistMarkers() {
        let converted = note.bodyMarkdown
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return line }
                if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                    return line
                }
                return "- [ ] " + line
            }
            .joined(separator: "\n")
        note.bodyMarkdown = converted
    }

    /// Tooltip — full date for both create and update, since the small
    /// "X 分钟前" caption alone is fuzzy when comparing several notes.
    private var absoluteTimeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let created = f.string(from: note.createdAt)
        let updated = f.string(from: note.updatedAt)
        return L(
            "Created \(created)\nUpdated \(updated)",
            "创建于 \(created)\n更新于 \(updated)"
        )
    }
}
