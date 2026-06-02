import SwiftUI
import SwiftData
import DorisCore

public extension Notification.Name {
    /// Posted (object = note `UUID`) when the user picks "Stick to
    /// desktop" from a note's context menu on macOS. The app-level
    /// StickyWindowManager observes it and floats a sticky window.
    static let dorisStickToDesktop = Notification.Name("doris.stickToDesktop")
}

/// Right-click context menu shared by every note row on macOS. Centralises
/// the scheduling quick picks (Today / Tomorrow / This Weekend / Next
/// Week / Pick date / Clear), the Pin · Open editor · Archive · Move to
/// trash actions for active rows, and Restore · Delete forever for trash
/// rows.
///
/// Apply to a row with `.noteContextMenu(for: note) { openEditor() }`.
/// The trailing closure is optional — pass it when the host can route
/// the user into the full editor (TodoRow's expand action, the anchor
/// Today row's tap-to-edit, etc.). Omit it on screens where there's no
/// editor to open from this context.
public extension View {
    @ViewBuilder
    func noteContextMenu(
        for note: Note,
        onOpenEditor: (() -> Void)? = nil
    ) -> some View {
        modifier(NoteContextMenuModifier(note: note, onOpenEditor: onOpenEditor))
    }
}

// MARK: - Modifier

private struct NoteContextMenuModifier: ViewModifier {
    let note: Note
    let onOpenEditor: (() -> Void)?

    @Environment(\.modelContext) private var ctx
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var showDatePicker = false
    @State private var confirmingPermanentDelete = false

    func body(content: Content) -> some View {
        content
            .contextMenu { menu }
            .popover(isPresented: $showDatePicker, arrowEdge: .trailing) {
                datePickerPopover
            }
            .alert(L("Permanently delete?", "彻底删除?"),
                   isPresented: $confirmingPermanentDelete) {
                Button(L("Delete forever", "彻底删除"), role: .destructive) {
                    ctx.delete(note)
                    try? ctx.save()
                }
                Button(L("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(L("This task can't be recovered after a permanent delete.",
                       "彻底删除后此任务无法恢复。"))
            }
    }

    // MARK: - Menu

    @ViewBuilder
    private var menu: some View {
        if note.deleted {
            // Trash row — limited actions
            Button {
                let now = Date()
                note.deleted = false
                note.deletedAt = nil
                note.updatedAt = now
            } label: {
                Label(L("Restore", "还原"), systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                confirmingPermanentDelete = true
            } label: {
                Label(L("Delete forever", "彻底删除"), systemImage: "trash.slash")
            }
        } else {
            scheduleMenu
            Divider()
            // Done toggle — sits right after Schedule because "I just
            // finished this" is the second most common quick action
            // after "schedule it for later". Stamps `completedAt` like
            // every other Done-toggle surface, so the Today tab's
            // "hide past + completed" filter sees it immediately.
            Button { toggleDone() } label: {
                Label(
                    note.done ? L("Mark not done", "标为未完成") : L("Mark as done", "标为已完成"),
                    systemImage: note.done ? "arrow.uturn.backward" : "checkmark.circle.fill"
                )
            }
            // One-shot "complete + archive" shortcut for the workflow
            // where finishing a task should also clear it from active
            // lists. Only offered when the row isn't already archived
            // — re-using it as "unarchive" would be confusing.
            if !note.archived {
                Button { completeAndArchive() } label: {
                    Label(L("Done & archive", "完成并归档"),
                          systemImage: "checkmark.seal.fill")
                }
            }
            // Two pin buckets — regular "置顶" and "长期" (long-term).
            // A note sits in exactly one (or neither); both set
            // note.pinned so the Today pinned area + "pinned first"
            // sort still pick them up, while note.longTerm chooses the
            // bucket.
            Button { togglePin() } label: {
                Label(
                    (note.pinned && !note.longTerm) ? L("Unpin", "取消置顶") : L("Pin to top", "置顶"),
                    systemImage: (note.pinned && !note.longTerm) ? "pin.slash" : "pin"
                )
            }
            Button { toggleLongTerm() } label: {
                Label(
                    (note.pinned && note.longTerm) ? L("Remove long-term", "取消长期") : L("Long-term", "长期"),
                    systemImage: "infinity"
                )
            }
            if let openEditor = onOpenEditor {
                Button { openEditor() } label: {
                    Label(L("Open editor", "打开编辑器"), systemImage: "doc.text")
                }
            }
            #if os(macOS)
            // Float this note as a sticky window on the desktop. The
            // mac app's StickyWindowManager observes this notification
            // (DorisUI has no AppKit dependency, so we decouple via
            // NotificationCenter rather than a direct call).
            if !note.archived {
                Button {
                    NotificationCenter.default.post(
                        name: .dorisStickToDesktop, object: note.id
                    )
                } label: {
                    Label(L("Stick to desktop", "贴到桌面"), systemImage: "macwindow.on.rectangle")
                }
            }
            #endif
            Divider()
            Button { toggleArchive() } label: {
                Label(
                    note.archived ? L("Unarchive", "解归档") : L("Archive", "归档"),
                    systemImage: note.archived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            Button(role: .destructive) {
                let now = Date()
                note.deleted = true
                note.deletedAt = now
                note.updatedAt = now
            } label: {
                Label(L("Move to trash", "移到回收站"), systemImage: "trash")
            }
        }
    }

    // MARK: - Schedule submenu

    @ViewBuilder
    private var scheduleMenu: some View {
        Menu {
            Button {
                setDue(QuickDate.today)
            } label: {
                Label(L("Today", "今天"), systemImage: "sun.max.fill")
            }
            Button {
                setDue(QuickDate.tomorrow)
            } label: {
                Label(L("Tomorrow", "明天"), systemImage: "sunrise.fill")
            }
            Button {
                setDue(QuickDate.thisWeekend)
            } label: {
                Label(L("This weekend", "本周末"), systemImage: "beach.umbrella.fill")
            }
            Button {
                setDue(QuickDate.nextWeek)
            } label: {
                Label(L("Next Monday", "下周一"), systemImage: "calendar")
            }
            Divider()
            Button {
                showDatePicker = true
            } label: {
                Label(L("Pick a date…", "选择日期…"), systemImage: "calendar.badge.plus")
            }
            if note.dueDate != nil {
                Divider()
                Button(role: .destructive) {
                    note.dueDate = nil
                    note.touch()
                } label: {
                    Label(L("Clear due date", "清除截止日期"),
                          systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            if let d = note.dueDate {
                Label(scheduleLabel(for: d), systemImage: "calendar")
            } else {
                Label(L("Schedule…", "排期…"), systemImage: "calendar")
            }
        }
    }

    private func scheduleLabel(for due: Date) -> String {
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let today = cal.startOfDay(for: Date())
        let prefix = L("Scheduled: ", "已排期: ")
        if dueDay < today {
            let days = cal.dateComponents([.day], from: dueDay, to: today).day ?? 0
            return prefix + L("\(days)d overdue", "逾期 \(days) 天")
        }
        if cal.isDateInToday(due)    { return prefix + L("Today", "今天") }
        if cal.isDateInTomorrow(due) { return prefix + L("Tomorrow", "明天") }
        return prefix + due.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Date picker popover (Pick a date…)

    private var datePickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Pick a due date", "选择截止日期"))
                .font(.headline)
                .foregroundStyle(.primary)

            DatePicker(
                L("Due date", "截止日期"),
                selection: Binding(
                    get: { note.dueDate ?? Calendar.current.startOfDay(for: Date()) },
                    set: { note.dueDate = $0; note.touch() }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(CyberPalette.neonCyan)

            HStack {
                if note.dueDate != nil {
                    Button(role: .destructive) {
                        note.dueDate = nil
                        note.touch()
                        showDatePicker = false
                    } label: {
                        Label(L("Clear", "清除"), systemImage: "calendar.badge.minus")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(L("Done", "完成")) { showDatePicker = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Mutations

    private func setDue(_ date: Date) {
        note.dueDate = date
        note.touch()
    }

    private func togglePin() {
        if note.pinned && !note.longTerm {
            note.pinned = false          // regular-pinned → unpin
        } else {
            note.pinned = true           // → regular pin (demote from long-term if needed)
            note.longTerm = false
        }
        note.touch()
    }

    private func toggleLongTerm() {
        if note.pinned && note.longTerm {
            note.pinned = false          // long-term → unpin entirely
            note.longTerm = false
        } else {
            note.pinned = true           // → long-term pin
            note.longTerm = true
        }
        note.touch()
    }

    private func toggleArchive() {
        let now = Date()
        note.archived.toggle()
        note.archivedAt = note.archived ? now : nil
        note.updatedAt = now
    }

    /// Flip `note.done` and stamp/clear `completedAt`. Same semantics
    /// as the Done toggle in the editor sheet so the calendar filter
    /// & strikethrough visuals react instantly.
    private func toggleDone() {
        let now = Date()
        note.done.toggle()
        note.completedAt = note.done ? now : nil
        note.updatedAt = now
    }

    /// One-click "complete + archive" — workflow shortcut for users who
    /// want "I'm done with this, get it off my active list" in one
    /// action instead of two menu trips. Idempotent if either flag is
    /// already in the target state.
    private func completeAndArchive() {
        let now = Date()
        if !note.done {
            note.done = true
            note.completedAt = now
        }
        if !note.archived {
            note.archived = true
            note.archivedAt = now
        }
        note.updatedAt = now
    }
}

// MARK: - QuickDate helpers

/// Calendar-aware quick-pick dates used by the Schedule submenu. All
/// dates are pinned to local-time start-of-day so they align with the
/// `DueDateChipButton` picker (which uses `.date` only).
public enum QuickDate {
    /// 00:00 today, local time.
    public static var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// 00:00 tomorrow, local time.
    public static var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: today)!
    }

    /// Upcoming Saturday at 00:00 local. If today *is* Saturday, returns
    /// today; if Sunday, jumps to next Saturday (6 days out).
    public static var thisWeekend: Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: today) // Sun=1 ... Sat=7
        let daysToSat = (7 - weekday + 7) % 7
        return cal.date(byAdding: .day, value: daysToSat, to: today)!
    }

    /// The Monday of next week at 00:00 local. From a Sunday → tomorrow;
    /// from any Mon–Sat → the Monday that's 2–7 days out (i.e. always
    /// strictly in the future, never "today" when today is Monday).
    public static var nextWeek: Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: today) // Sun=1 ... Sat=7
        let daysToMon: Int = weekday == 1 ? 1 : (9 - weekday)
        return cal.date(byAdding: .day, value: daysToMon, to: today)!
    }
}
