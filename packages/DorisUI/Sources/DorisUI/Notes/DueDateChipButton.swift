import SwiftUI
import DorisCore

/// Reusable due-date chip used in both Mac `InlineNoteEditor` and
/// iOS `NoteDetailScreen`. Tapping opens a popover (Mac) or sheet (iOS)
/// with a date picker and a "Clear" button.
public struct DueDateChipButton: View {
    @Bindable public var note: Note
    /// When `true` (default), render at the small size that fits inline
    /// inside `TodoRow` — a tiny dated chip / barely-there calendar+ in
    /// the undated state. When `false`, render at the larger size that
    /// matches the Pin / Checklist / Done toggles in the editor's
    /// attribute row, including an always-visible outlined pill in the
    /// undated state so the row reads as a coherent set.
    public var compact: Bool
    @State private var showingPicker = false
    /// Month the calendar is showing. Separate from the due date so paging
    /// through months doesn't change the note, and so opening the popover
    /// lands on the month of the existing due date rather than always today.
    @State private var displayedMonth = Date()

    public init(note: Note, compact: Bool = true) {
        self.note = note
        self.compact = compact
    }

    public var body: some View {
        Button {
            // Open on the month being edited — landing on today when the due
            // date is months away meant paging back before you could see it.
            displayedMonth = note.dueDate ?? Date()
            showingPicker = true
        } label: {
            if let due = note.dueDate {
                // Dated → prominent color-coded chip. Smart label:
                // overdue / today / tomorrow / weekday-this-week /
                // full date — gives the user "when is this due" at
                // a glance instead of just "May 20".
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(compact ? .system(size: 9, weight: .semibold) : .caption)
                    Text(smartDueLabel(for: due))
                        .font(compact
                              ? .caption2.weight(.semibold).monospacedDigit()
                              : .caption.weight(.medium).monospacedDigit())
                }
                .padding(.horizontal, compact ? 7 : 10)
                .padding(.vertical, compact ? 3 : 5)
                .background(Capsule().fill(chipColor.opacity(compact ? 0.15 : 0.18)))
                .overlay(Capsule().stroke(chipColor.opacity(compact ? 0.45 : 0.55),
                                          lineWidth: compact ? 0.6 : 0.8))
                .foregroundStyle(chipColor)
            } else if compact {
                // Compact undated → tiny icon-only affordance for use
                // in `TodoRow`, where the row already has plenty of
                // chrome and a full pill would crowd things.
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.35))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            } else {
                // Editor undated → outlined pill with icon + "Schedule"
                // label, matching the visual weight of the sibling Pin
                // / Checklist / Done toggles. Earlier iteration showed
                // only a tiny icon which visually broke the editor row.
                Label(L("Schedule", "排期"), systemImage: "calendar.badge.plus")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 0.6))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .help(L("Schedule…", "排期…"))
        .onChange(of: note.dueDate) { _, newDate in
            if let date = newDate {
                DueDateNotifier.schedule(
                    noteID: note.id, title: note.title, dueDate: date, done: note.done
                )
            } else {
                DueDateNotifier.cancel(noteID: note.id)
            }
        }
        #if os(macOS)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            dueDatePopover
                .padding(16)
                // Wider than before: the quick row needs four comfortable
                // targets across, and the calendar's day cells get more room
                // instead of being squeezed to ~11pt hit areas.
                .frame(width: 340)
        }
        #else
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                dueDatePickerContent
                    .navigationTitle(L("Set due date", "设置截止日期"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("Done", "完成")) { showingPicker = false }
                                .foregroundStyle(CyberPalette.neonCyan)
                        }
                    }
                    .background { CyberBackground().ignoresSafeArea() }
            }
            .presentationDetents([.medium])
        }
        #endif
    }

    private var chipColor: Color {
        guard let due = note.dueDate else { return CyberPalette.neonCyan }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        if due < startOfToday { return .red }
        if Calendar.current.isDateInToday(due) { return .yellow }
        return CyberPalette.neonCyan
    }

    /// "今天 / 明天 / 周X / 5月20日" labels — mirrors the same logic
    /// TodayCalendarRow + NoteContextMenu use, so the displayed
    /// scheduled-date copy stays consistent across the product.
    private func smartDueLabel(for due: Date) -> String {
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let today = cal.startOfDay(for: Date())
        if dueDay < today {
            let days = cal.dateComponents([.day], from: dueDay, to: today).day ?? 0
            if days == 0 { return L("Today", "今天") }
            return L("\(days)d overdue", "逾期 \(days) 天")
        }
        if cal.isDateInToday(due) { return L("Today", "今天") }
        if cal.isDateInTomorrow(due) { return L("Tomorrow", "明天") }
        let days = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days < 7 {
            return due.formatted(.dateTime.weekday(.abbreviated))
        }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }

    #if os(macOS)
    /// Presets first, calendar second.
    ///
    /// Almost every due date is "today", "tomorrow", or "the weekend", and
    /// the bare graphical `DatePicker` made all three a hunt through a grid
    /// of 11pt day cells. One click now covers the common cases; the calendar
    /// stays for the rest.
    private var dueDatePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quickRow
            Divider().opacity(0.5)
            calendar
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L("Due date", "截止日期"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            // The current value, so the popover states what it's editing —
            // previously you had to infer it from the highlighted cell, which
            // showed today whether or not a date was actually set.
            Text(note.dueDate.map { $0.formatted(.dateTime.year().month().day()) }
                 ?? L("Not set", "未设定"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var quickRow: some View {
        HStack(spacing: 6) {
            quickButton(L("Today", "今天"), "sun.max.fill", QuickDate.today)
            quickButton(L("Tomorrow", "明天"), "sunrise.fill", QuickDate.tomorrow)
            quickButton(L("Weekend", "周末"), "beach.umbrella.fill", QuickDate.thisWeekend)
            quickButton(L("Next wk", "下周"), "calendar", QuickDate.nextWeek)
        }
    }

    private func quickButton(_ title: String, _ symbol: String, _ date: Date) -> some View {
        let isCurrent = note.dueDate.map {
            Calendar.current.isDate($0, inSameDayAs: date)
        } ?? false
        return Button {
            setDue(date)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? CyberPalette.neonCyan.opacity(0.22)
                                    : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? CyberPalette.neonCyan.opacity(0.7) : .clear,
                                  lineWidth: 1)
            )
            .foregroundStyle(isCurrent ? CyberPalette.neonCyan : Color.primary.opacity(0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var calendar: some View {
        MonthCalendar(
            month: $displayedMonth,
            selected: note.dueDate,
            onPick: { setDue($0) }
        )
    }

    private var footer: some View {
        HStack {
            if note.dueDate != nil {
                Button {
                    note.dueDate = nil
                    note.touch()
                    DueDateNotifier.cancel(noteID: note.id)
                    showingPicker = false
                } label: {
                    Label(L("Clear", "清除"), systemImage: "calendar.badge.minus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.9))
            }
            Spacer()
            Button(L("Done", "完成")) { showingPicker = false }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
        }
    }

    /// Single write path so a date picked ANY way also (re)schedules its
    /// reminder — the old popover set `dueDate` straight from the calendar
    /// binding and never told `DueDateNotifier`, so dates chosen there
    /// silently never notified.
    private func setDue(_ date: Date, close: Bool = true) {
        note.dueDate = date
        note.touch()
        DueDateNotifier.schedule(noteID: note.id, title: note.title,
                                 dueDate: date, done: note.done)
        if close { showingPicker = false }
    }
    #endif

    private var dueDatePickerContent: some View {
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
                    showingPicker = false
                } label: {
                    Label(L("Clear due date", "清除截止日期"), systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}
