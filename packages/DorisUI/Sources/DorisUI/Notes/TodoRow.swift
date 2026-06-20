import SwiftUI
import SwiftData
import DorisCore
#if canImport(AppKit)
import AppKit
#endif

/// View mode for the TODO list. Three filters partition every note:
///   - `.active`   →  not archived, not deleted
///   - `.archived` →  archived but not deleted
///   - `.trash`    →  soft-deleted (recoverable from this view)
public enum TodoFilter {
    case active
    case archived
    case trash
}

/// One row in the TODO-style notes list. Each note IS a top-level task
/// — checkbox to toggle done, inline-editable title, expand button to
/// open the full editor (body / sub-checklist).
///
/// Press Enter on the title field → the host's `onSubmit` fires, which
/// should create a fresh empty task below and route focus to it.
public struct TodoRow: View {
    @Bindable public var note: Note
    /// Host-managed focus target — the id of the row whose title field
    /// should hold the keyboard. A PLAIN `Binding`, not a `@FocusState`
    /// binding: the macOS title field is an AppKit `NSTextField` that
    /// drives first-responder itself, so the parent uses `@State` (a
    /// `@FocusState` set with no matching `.focused()` modifier would
    /// revert to nil and the row would never focus). TodoRow is macOS-only.
    public var focused: Binding<UUID?>
    /// Called when the user presses Enter while editing the title.
    public var onSubmit: () -> Void
    /// Called when the user presses Backspace on an EMPTY title. The host
    /// should delete this (empty) task and move focus to the END of the
    /// previous row. macOS only — the AppKit field intercepts the key.
    public var onDeleteEmpty: () -> Void
    /// Called when the user clicks the expand icon — the host opens
    /// the full inline editor for body / sub-checklist editing.
    public var onExpand: () -> Void
    /// Called when another row is dropped onto THIS row — the host
    /// re-orders so the dragged note lands right before this one.
    /// Argument is the dragged note's UUID (encoded as String for
    /// transferable simplicity).
    public var onDropBefore: (UUID) -> Void
    /// Called when the user presses ↑ while editing the title. The host
    /// should move keyboard focus to the previous row.
    public var onMoveUp: () -> Void
    /// Called when the user presses ↓ while editing the title. The host
    /// should move keyboard focus to the next row.
    public var onMoveDown: () -> Void

    @Environment(\.modelContext) private var ctx
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var hovering = false
    @State private var confirmingDelete = false
    @State private var isDropTarget = false

    public init(
        note: Note,
        focused: Binding<UUID?>,
        onSubmit: @escaping () -> Void,
        onExpand: @escaping () -> Void,
        onDeleteEmpty: @escaping () -> Void = {},
        onDropBefore: @escaping (UUID) -> Void = { _ in },
        onMoveUp: @escaping () -> Void = {},
        onMoveDown: @escaping () -> Void = {}
    ) {
        self.note = note
        self.focused = focused
        self.onSubmit = onSubmit
        self.onExpand = onExpand
        self.onDeleteEmpty = onDeleteEmpty
        self.onDropBefore = onDropBefore
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Pin + checkbox sit in a tight inner cluster (spacing 2)
            // so the leading edge of the row doesn't feel like wasted
            // gutter. Each control still has a comfortable hit area —
            // we just stripped the surrounding air, not the target.
            HStack(spacing: 2) {
                // Pin toggle — leftmost, in the slot the drag handle
                // used to occupy. Pinned rows always show the saturated
                // pink pin; unpinned rows show only on hover. Whole-row
                // drag-to-reorder lives on the row body below — there
                // is no separate drag handle.
                Button {
                    note.pinned.toggle()
                    if !note.pinned { note.longTerm = false }  // don't leave a dangling long-term flag
                    note.updatedAt = Date()
                } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(note.pinned
                                         ? CyberPalette.neonPink
                                         : Color.primary.opacity(hovering ? 0.45 : 0.0))
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(note.pinned
                      ? L("Unpin", "取消置顶")
                      : L("Pin to top", "置顶"))

                // Done checkbox. Toggling done also stamps / clears
                // `completedAt` — that timestamp is what the upcoming
                // "archive yesterday's done tasks" feature reads.
                // Completing a task fires a HeroEvents celebration so
                // the avatar reacts; unchecking is silent.
                Button {
                    note.done.toggle()
                    let now = Date()
                    note.updatedAt = now
                    note.completedAt = note.done ? now : nil
                    if note.done {
                        // Cancel any pending due-date reminder — task is done.
                        DueDateNotifier.cancel(noteID: note.id)
                        Task { @MainActor in HeroEvents.shared.celebrate() }
                    } else if let due = note.dueDate {
                        // Re-schedule the reminder if the task is un-done.
                        DueDateNotifier.schedule(noteID: note.id, title: note.title,
                                                 dueDate: due, done: false)
                    }
                } label: {
                    Image(systemName: note.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(note.done
                                         ? CyberPalette.neonCyan
                                         : Color.primary.opacity(0.55))
                        .frame(width: 16, height: 18)
                }
                .buttonStyle(.plain)
                .help(note.done
                      ? L("Mark not done", "取消完成")
                      : L("Mark done", "标记完成"))
            }

            // Inline-editable title.
            #if os(macOS)
            // AppKit-backed so we can intercept the field editor's keys:
            //   Return            → onSubmit       (new task below)
            //   Backspace (empty) → onDeleteEmpty  (delete + merge up)
            // SwiftUI's TextField can't — the field editor eats those keys
            // before .onSubmit / .onKeyPress see them. Focus is driven by
            // `focused` (the parent's @FocusState), exactly like the
            // checklist editor's ChecklistItemField. On focus the caret
            // lands at the END of the text, which gives both behaviors we
            // want for free: a new (empty) row → caret at start; a merge
            // target (has text) → caret at end.
            TodoTitleField(
                text: $note.title,
                placeholder: L("New task", "新任务"),
                done: note.done,
                isFocused: focused.wrappedValue == note.id,
                onFocusChange: { gained in
                    if gained { focused.wrappedValue = note.id }
                    else if focused.wrappedValue == note.id { focused.wrappedValue = nil }
                },
                onSubmit: onSubmit,
                onDeleteEmpty: onDeleteEmpty,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .onChange(of: note.title) { _, _ in note.updatedAt = Date() }
            #else
            // iOS path is dead code (iOS uses NoteRow) but must compile.
            // No `.focused()` — `focused` is a plain Binding now.
            TextField(
                L("New task", "新任务"),
                text: $note.title
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .strikethrough(note.done, color: .secondary)
            .foregroundStyle(note.done
                             ? Color.primary.opacity(0.45)
                             : Color.primary)
            .onSubmit(onSubmit)
            .onChange(of: note.title) { _, _ in note.updatedAt = Date() }
            #endif

            Spacer(minLength: 0)

            // Action cluster — hover-only so resting rows stay clean.
            // Sits LEFT of the expand-icon and time so the always-on
            // info (whether the note has body content + when it was
            // last touched) anchors the right edge of the row, while
            // the action buttons live just inside that.
            HStack(spacing: 4) {
                primaryActionButton   // archive / unarchive / restore
                deleteActionButton    // soft-delete / permanent-delete
            }
            .opacity(hovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: hovering)

            // Expand → open full editor for body / sub-checklist.
            // Icon swaps to a "doc" if the note has body content.
            Button(action: onExpand) {
                Image(systemName: hasBody ? "doc.text.fill" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hasBody
                                     ? CyberPalette.neonPink.opacity(hovering ? 0.9 : 0.55)
                                     : Color.primary.opacity(hovering ? 0.7 : 0.3))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(L("Open editor", "打开编辑器"))

            // Due-date chip — rightmost, always visible. Replaces the
            // "last-modified relative time" that used to live here:
            // when a row HAS a due date that's what the user actually
            // cares about ("oh, this is for today"), and when there
            // isn't one the chip becomes a discoverable "schedule"
            // affordance. Avoids the right-click-on-TextField pitfall
            // where macOS's text editing menu hijacks the gesture and
            // the user can't reach the schedule submenu.
            DueDateChipButton(note: note)
        }
        .padding(.horizontal, 8)
        // Bumped vertical padding now that rows touch (parent VStack
        // spacing is 0). Comfortable click target without a dead gap
        // between rows where clicks would land on neither.
        .padding(.vertical, 7)
        .background(
            // Hover highlight covers the entire row extent (hit-tested
            // by `contentShape` below). Resting state is fully clear so
            // adjacent rows don't visually merge into a fat blob.
            Rectangle()
                .fill(hovering
                      ? Color.primary.opacity(0.06)
                      : Color.clear)
        )
        .overlay(alignment: .top) {
            // Drop indicator — a 2pt cyan bar at the top of this row
            // when another row is being dragged onto it. Tells the user
            // "your dragged item will land HERE (above this row)".
            if isDropTarget {
                Rectangle()
                    .fill(CyberPalette.neonCyan)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            // Hairline separator between rows — barely visible, just
            // enough to give the eye a row boundary without looking
            // like a heavy table grid.
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Whole-row drag to reorder. SwiftUI requires a deliberate
        // press-and-drag to start a drag, so quick taps on the title
        // TextField, checkbox, pin, action buttons etc. still hit
        // their intended targets — only an actual drag picks up the
        // row. Replaces the old dedicated 3-line drag handle.
        .draggable(note.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            // Only accept the first item — we encode UUIDs as String
            // for simplicity. Reject self-drops (dropping a row on
            // itself is a no-op).
            guard let raw = items.first,
                  let dragged = UUID(uuidString: raw),
                  dragged != note.id else { return false }
            onDropBefore(dragged)
            return true
        } isTargeted: { hovering in
            isDropTarget = hovering
        }
        // Click anywhere on the row → focus its title for editing.
        // Inner controls (checkbox button, expand button, delete /
        // archive buttons, the TextField itself) absorb their own
        // clicks first via SwiftUI's gesture priority, so this only
        // fires when the user actually clicked on a "blank" part of
        // the row (margins around the title, gap between title and
        // time, etc). Without this you had to land precisely on the
        // text glyphs to start editing.
        .onTapGesture {
            focused.wrappedValue = note.id
        }
        // Confirmation alert — only used for PERMANENT delete (from
        // the Trash view). Soft-delete (Active/Archived → Trash) goes
        // through silently because Trash is recoverable.
        .alert(L("Permanently delete?", "彻底删除?"),
               isPresented: $confirmingDelete) {
            Button(L("Delete forever", "彻底删除"), role: .destructive) {
                ctx.delete(note)
                try? ctx.save()
            }
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("This task can't be recovered after a permanent delete.",
                   "彻底删除后此任务无法恢复。"))
        }
        // Whole-row right-click menu: scheduling quick picks + pin /
        // open / archive / trash. Lives at the bottom of the modifier
        // chain so it doesn't interfere with the drag/drop or hover
        // gestures above.
        .noteContextMenu(for: note, onOpenEditor: onExpand)
    }

    // MARK: - Action buttons

    /// Left action: archive / unarchive (in active/archived view) or
    /// restore (in trash view). Icon + tooltip flip based on state.
    @ViewBuilder
    private var primaryActionButton: some View {
        if note.deleted {
            // Trash row → restore button
            Button {
                let now = Date()
                note.deleted = false
                note.deletedAt = nil
                note.updatedAt = now
            } label: {
                actionIcon("arrow.uturn.backward", tint: CyberPalette.neonCyan)
            }
            .buttonStyle(.plain)
            .help(L("Restore (back to active)", "还原(回到活动)"))
        } else {
            // Active or archived row → archive toggle
            Button {
                let now = Date()
                note.archived.toggle()
                note.archivedAt = note.archived ? now : nil
                note.updatedAt = now
            } label: {
                actionIcon(note.archived ? "tray.and.arrow.up" : "archivebox",
                           tint: CyberPalette.neonCyan)
            }
            .buttonStyle(.plain)
            .help(note.archived
                  ? L("Unarchive (back to active)", "解归档(回到活动)")
                  : L("Archive", "归档"))
        }
    }

    /// Right action: trash / permanent-delete. In active/archived
    /// view, soft-delete goes through with no confirmation (the row
    /// is recoverable from Trash). In trash view, this is the
    /// destructive permanent-delete path with a confirmation alert.
    @ViewBuilder
    private var deleteActionButton: some View {
        Button {
            if note.deleted {
                confirmingDelete = true   // permanent — needs confirmation
            } else {
                let now = Date()
                note.deleted = true
                note.deletedAt = now
                note.updatedAt = now
            }
        } label: {
            actionIcon(note.deleted ? "trash.slash" : "trash",
                       tint: CyberPalette.neonPink)
        }
        .buttonStyle(.plain)
        .help(note.deleted
              ? L("Delete forever", "彻底删除")
              : L("Move to trash", "移到回收站"))
    }

    /// Shared visual style for the two action icons — same size / shape /
    /// hover treatment so the cluster reads as a unit. The right-click
    /// menu is attached to the whole row body via `.noteContextMenu`,
    /// not to this icon, so users can right-click anywhere on the row.
    private func actionIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint.opacity(0.85))
            .frame(width: 18, height: 18)
            .background(
                Circle().fill(tint.opacity(0.10))
            )
            .overlay(
                Circle().stroke(tint.opacity(0.3), lineWidth: 0.5)
            )
    }

    private var hasBody: Bool {
        !note.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if os(macOS)

/// Single-line AppKit title field for a TODO row. Mirrors the checklist
/// editor's `ChecklistItemField`: it exists only so we can intercept the
/// field editor's command keys (Return → new task, Backspace-on-empty →
/// delete-and-merge-up), which a SwiftUI `TextField` can't. On focus it
/// drops the caret at the END of the text — for a freshly-created empty
/// row that's position 0 (the start), and for a merge target it's the end.
struct TodoTitleField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var done: Bool
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Void
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isEditable = true
        tf.isSelectable = true
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.usesSingleLineMode = true
        tf.lineBreakMode = .byTruncatingTail
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.font = NSFont.preferredFont(forTextStyle: .subheadline)
        tf.placeholderString = placeholder
        tf.delegate = context.coordinator
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        if tf.stringValue != text { tf.stringValue = text }
        tf.placeholderString = placeholder
        // Done → dimmed. The checkbox carries the "done" signal; AppKit
        // strikethrough on an editable field fights the field editor, so
        // we dim like the checklist editor instead of striking through.
        tf.textColor = done ? NSColor.labelColor.withAlphaComponent(0.45) : .labelColor

        // Self-healing focus: whenever SwiftUI marks this row focused we
        // become first responder and drop the caret at the end. The
        // shared helper retries until the field is in a window — without
        // that, a new row inside the menu-bar panel (whose NSView has a
        // nil window for a few ticks) never grabs the caret.
        if isFocused { dorisFocusFieldToEnd(tf) }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoTitleField
        init(_ parent: TodoTitleField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
        func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocusChange(true) }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocusChange(false) }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            // Decide arrow / shortcut handling from the RAW keystroke, not
            // the command selector. In a single-line field the field editor
            // maps ↑/↓ to move-to-start/end-of-document (not moveUp:/
            // moveDown:), so matching on the selector name silently misses
            // them and the caret jumps to the line head/tail. keyCode is
            // unambiguous.
            if let event = NSApp.currentEvent, event.type == .keyDown {
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                // Ctrl+A → line head, Ctrl+Z → line tail.
                if mods == .control {
                    switch event.charactersIgnoringModifiers?.lowercased() {
                    case "a": textView.moveToBeginningOfLine(nil); return true
                    case "z": textView.moveToEndOfLine(nil);       return true
                    default:  break
                    }
                }
                // Bare ↑ / ↓ (arrows carry .function/.numericPad flags, but
                // none of cmd/ctrl/opt/shift) → switch task rows.
                if mods.isEmpty {
                    switch event.keyCode {
                    case 126: parent.onMoveUp();   return true   // ↑
                    case 125: parent.onMoveDown(); return true   // ↓
                    default:  break
                    }
                }
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
                parent.onDeleteEmpty()
                return true
            }
            return false
        }
    }
}

#endif // os(macOS)
