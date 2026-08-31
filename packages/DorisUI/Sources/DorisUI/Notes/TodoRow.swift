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
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var lang = LanguageSettings.shared
    /// Observed so the row's focus button flips to "stop" (and back) the
    /// moment a session starts or ends anywhere — including from the notch
    /// ring or the context menu.
    @ObservedObject private var focus = FocusTimer.shared
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
                colorScheme: colorScheme,
                isFocused: focused.wrappedValue == note.id,
                onFocusChange: { gained in
                    if gained { focused.wrappedValue = note.id }
                    else if focused.wrappedValue == note.id { focused.wrappedValue = nil }
                },
                onSubmit: onSubmit,
                onDeleteEmpty: onDeleteEmpty,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onDoubleClick: onExpand
            )
            // Constrain width so the field wraps to the available space (and
            // reports its multi-line height) instead of growing horizontally.
            .frame(maxWidth: .infinity, alignment: .leading)
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

            // No Spacer: the title field above takes maxWidth .infinity, so
            // it fills the gap and pushes this trailing cluster to the right
            // edge (a Spacer here would split the slack with the field and
            // halve its width, wrapping the text too early).

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

            // Focus (pomodoro). Always visible when THIS task is the active
            // session — it doubles as the "what am I on" indicator, so it
            // must not be hidden behind hover like the archive/delete pair.
            // Sub-tasks got a ▷ in the checklist editor from the start;
            // top-level tasks only had the right-click menu, which is a poor
            // place for something you reach for several times a day.
            focusButton

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
        // Rows touch (parent VStack spacing is 0), so the row still needs
        // enough height to be a comfortable target — but most of that height
        // now belongs to the title field itself (`verticalPadding`), where it
        // is EDITABLE rather than dead. Keeping the old 7pt here on top of
        // that would just make rows tall again; this trims the inert part and
        // lets the field own the space.
        .padding(.vertical, 3)
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

    /// Start / stop a focus session on this task. A menu when idle (so the
    /// duration is one click away rather than a separate step), a plain stop
    /// button while this task is the one running.
    @ViewBuilder
    private var focusButton: some View {
        let isFocusedTask = focus.isFocused(noteID: note.id)
        if isFocusedTask {
            Button { FocusTimer.shared.stop() } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CyberPalette.neonPink)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(L("Stop focus", "停止专注"))
        } else if !note.done {
            // Done tasks don't get the affordance — starting a pomodoro on
            // something already finished is never the intent.
            Menu {
                ForEach([15, 25, 45], id: \.self) { m in
                    Button(L("\(m) min", "\(m) 分钟")) {
                        FocusTimer.shared.start(noteID: note.id, title: note.title,
                                                subtask: nil, minutes: m)
                    }
                }
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(hovering ? 0.7 : 0.25))
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Start focus", "开始专注"))
        }
    }

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
    /// Active theme scheme, passed from SwiftUI. We pin the field's
    /// `appearance` to it so `.labelColor` resolves deterministically —
    /// otherwise frequent `updateNSView` passes can momentarily resolve it
    /// against the wrong appearance (black text on the dark panel → the
    /// "text flickers / goes invisible" bug).
    var colorScheme: ColorScheme
    var isFocused: Bool
    var onFocusChange: (Bool) -> Void
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Void
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    /// Double-click on a row that ISN'T already being edited → open the task.
    /// Same action as the "open editor" toolbar button, which stays.
    var onDoubleClick: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WrappingTextField {
        // WrappingTextField (the same self-sizing field the checklist uses):
        // long titles wrap onto multiple lines and the row grows to fit,
        // instead of truncating to one line. Enter still fires onSubmit (the
        // delegate intercepts insertNewline), so multi-line display doesn't
        // turn into multi-line input.
        let tf = WrappingTextField()
        // Custom cell so the text stays centred once `verticalPadding` makes
        // the field taller than its glyphs. Must be installed before any
        // other cell configuration below, which would otherwise be lost.
        let cell = InsetTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = false
        cell.drawsBackground = false
        tf.cell = cell
        tf.isEditable = true
        tf.isSelectable = true
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.usesSingleLineMode = false
        tf.maximumNumberOfLines = 0
        tf.lineBreakMode = .byWordWrapping
        tf.cell?.wraps = true
        tf.cell?.isScrollable = false
        // 14pt, not `.subheadline` — that resolves to 11pt on macOS, which
        // made task titles small and (because the caret is line-height) gave
        // a stubby insertion point that was hard to place accurately.
        tf.font = NSFont.systemFont(ofSize: 14)
        // Grow the editable strip beyond the glyphs so clicking anywhere in
        // the row's text column starts editing, rather than only the few
        // points the characters happen to occupy.
        tf.verticalPadding = 5

        tf.placeholderString = placeholder
        tf.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        tf.delegate = context.coordinator
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tf.setContentHuggingPriority(.required, for: .vertical)
        context.coordinator.installArrowMonitor(for: tf)
        context.coordinator.installDoubleClickMonitor(for: tf)
        return tf
    }

    static func dismantleNSView(_ nsView: WrappingTextField, coordinator: Coordinator) {
        coordinator.removeArrowMonitor()
    }

    func updateNSView(_ tf: WrappingTextField, context: Context) {
        let c = context.coordinator
        c.parent = self
        // Pin the appearance so `.labelColor` always resolves to the right
        // light/dark value (deterministic, no flicker-to-invisible).
        let appName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if tf.appearance?.name != appName { tf.appearance = NSAppearance(named: appName) }
        if tf.stringValue != text { tf.stringValue = text }
        if tf.placeholderString != placeholder { tf.placeholderString = placeholder }
        // Only touch textColor when `done` actually flips. Comparing NSColor
        // instances is unreliable for dynamic / alpha colors, so the old
        // `tf.textColor != target` re-assigned (and redrew) on every pass —
        // that per-render redraw is what made rows flicker on unrelated
        // refreshes (focus change, CloudKit sync, autosave).
        if c.appliedDone != done {
            c.appliedDone = done
            tf.textColor = done ? NSColor.labelColor.withAlphaComponent(0.45) : .labelColor
        }

        // Self-healing focus: whenever SwiftUI marks this row focused we
        // become first responder and drop the caret at the end. The
        // shared helper retries until the field is in a window — without
        // that, a new row inside the menu-bar panel (whose NSView has a
        // nil window for a few ticks) never grabs the caret.
        if isFocused { dorisFocusFieldToEnd(tf) }
    }

    /// Report the WRAPPED height at SwiftUI's proposed width so the row grows
    /// to fit a multi-line title instead of clipping to one line. The
    /// `layout()` invalidation alone wasn't enough — SwiftUI kept the
    /// single-line height it measured first; this hands it the real height
    /// for the actual width.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WrappingTextField, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width != .infinity else { return nil }
        if abs(nsView.preferredMaxLayoutWidth - width) > 0.5 {
            nsView.preferredMaxLayoutWidth = width
            nsView.invalidateIntrinsicContentSize()
        }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoTitleField
        /// Last-applied `done` so we only re-color when it actually flips.
        var appliedDone: Bool?
        init(_ parent: TodoTitleField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
        func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocusChange(true) }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocusChange(false) }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            // Ctrl+A → line head, Ctrl+Z → line tail. Decided from the raw
            // event because in a single-line field these aren't reliably
            // distinguishable from arrows at the selector level.
            // (Bare ↑/↓ row-switching is handled by a key monitor — see
            // `installArrowMonitor` — because a single-line field editor
            // does NOT route plain arrows through this delegate method.)
            if let event = NSApp.currentEvent, event.type == .keyDown,
               event.modifierFlags.intersection([.command, .control, .option, .shift]) == .control {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a": textView.moveToBeginningOfLine(nil); return true
                case "z": textView.moveToEndOfLine(nil);       return true
                default:  break
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

        /// Bare ↑/↓ never reach `control(_:textView:doCommandBy:)` in a
        /// single-line field editor (it consumes them as caret moves), so we
        /// catch them one level earlier with a local key-event monitor. The
        /// monitor only acts while THIS field is the one being edited, and
        /// swallows the arrow so the caret doesn't jump to the line head/tail.
        var arrowMonitor: Any?
        var clickMonitor: Any?

        func installArrowMonitor(for field: NSTextField) {
            guard arrowMonitor == nil else { return }
            arrowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak field] event in
                guard let self, let field,
                      let editor = field.currentEditor(),
                      field.window?.firstResponder === editor
                else { return event }

                // ⌘↩ while editing → open the task. Checked before the
                // no-modifiers guard below, which exists for the plain arrows.
                if event.keyCode == 36, event.modifierFlags.contains(.command) {
                    field.window?.makeFirstResponder(nil)
                    self.parent.onDoubleClick()
                    return nil
                }

                guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return event }
                // See ChecklistItemField: a local monitor outruns the input
                // method, so the arrows have to be handed back while it is
                // composing or the candidate list can't be navigated.
                if let tv = editor as? NSTextView, tv.hasMarkedText() { return event }
                switch event.keyCode {
                case 126: self.parent.onMoveUp();   return nil   // ↑
                case 125: self.parent.onMoveDown(); return nil   // ↓
                default:  return event
                }
            }
        }

        /// Double-click anywhere on the title → open the task.
        ///
        /// Has to be a local event monitor, not a gesture recognizer on the
        /// field: the first click hands first-responder status to the field
        /// editor (an NSTextView subview), so the second click is delivered
        /// there and a recognizer on the NSTextField never sees it — it just
        /// became word-selection. A local monitor sees the event before
        /// dispatch, whoever is focused. Same mechanism the arrow keys above
        /// already rely on.
        func installDoubleClickMonitor(for field: NSTextField) {
            guard clickMonitor == nil else { return }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak field] event in
                guard let self, let field, event.clickCount == 2,
                      let window = field.window, event.window === window
                else { return event }
                // Only ours: the monitor is global to the app, so every row's
                // field would otherwise react to a double-click in any of them.
                let local = field.convert(event.locationInWindow, from: nil)
                guard field.bounds.contains(local) else { return event }

                field.window?.makeFirstResponder(nil)
                self.parent.onDoubleClick()
                return nil          // swallow, so it doesn't also select a word
            }
        }

        func removeArrowMonitor() {
            if let m = arrowMonitor { NSEvent.removeMonitor(m); arrowMonitor = nil }
            if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        }

        deinit { removeArrowMonitor() }
    }
}

#endif // os(macOS)
