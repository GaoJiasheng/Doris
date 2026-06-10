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

    public init(note: Note, compact: Bool = true) {
        self.note = note
        self.compact = compact
    }

    public var body: some View {
        Button {
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
                .frame(width: 300)
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
    private var dueDatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Due date", "截止日期"))
                .font(.headline)
            DatePicker(
                "",
                selection: Binding(
                    get: { note.dueDate ?? Date() },
                    set: { note.dueDate = $0; note.touch() }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            if note.dueDate != nil {
                Button(role: .destructive) {
                    note.dueDate = nil
                    note.touch()
                    showingPicker = false
                } label: {
                    Label(L("Clear due date", "清除截止日期"), systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
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
