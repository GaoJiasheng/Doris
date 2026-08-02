import SwiftUI

/// A month grid we draw ourselves.
///
/// Replaces SwiftUI's `.graphical` DatePicker, which on macOS can't be made
/// to fit a design: it keeps its own intrinsic size (so it sits small and
/// left-aligned in any wider container), draws a blue system bezel that reads
/// as an error box on a dark panel, and gives ~11pt day cells that are
/// genuinely hard to hit. None of that is reachable through the SwiftUI API.
///
/// Drawing it here means the cells fill the available width, the palette
/// matches the app, and a day is a comfortable target.
struct MonthCalendar: View {
    @Binding var month: Date
    /// Currently selected day, if any. Nil renders no selection — unlike the
    /// system picker, which always highlights *something* and so implied a
    /// due date was set when none was.
    var selected: Date?
    var onPick: (Date) -> Void

    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 8) {
            monthHeader
            weekdayHeader
            grid
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: 2) {
            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            stepper("chevron.left") { shift(-1) }
            Button {
                month = Date()
            } label: {
                Text(L("Today", "今天"))
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            stepper("chevron.right") { shift(1) }
        }
    }

    private func stepper(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                // Deliberately larger than the glyph — the system picker's
                // arrows were a few points across and easy to miss.
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.7))
    }

    private func shift(_ months: Int) {
        if let next = cal.date(byAdding: .month, value: months, to: month) {
            month = next
        }
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Weekday initials rotated to the locale's first weekday — hardcoding a
    /// Sunday start would mislabel every column for a Monday-start locale.
    private var orderedWeekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(weeks, id: \.first) { week in
                HStack(spacing: 2) {
                    ForEach(week, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let isToday = cal.isDateInToday(day)

        return Button {
            onPick(day)
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                .foregroundStyle(
                    isSelected ? Color.white
                    : inMonth ? Color.primary.opacity(0.9)
                    : Color.primary.opacity(0.28)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? CyberPalette.neonCyan.opacity(0.85) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isToday && !isSelected
                                      ? CyberPalette.neonCyan.opacity(0.55) : .clear,
                                      lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Whole weeks covering `month`, including the leading/trailing days of
    /// the neighbouring months so every row has seven cells.
    private var weeks: [[Date]] {
        guard let monthRange = cal.range(of: .day, in: .month, for: month),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }

        let leading = (cal.component(.weekday, from: firstOfMonth) - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: firstOfMonth) else { return [] }

        // Enough rows to cover the month from that start — 4 to 6 depending on
        // length and offset. Computing it (rather than always drawing 6) keeps
        // the popover from growing a blank trailing row.
        let total = leading + monthRange.count
        let rows = Int(ceil(Double(total) / 7.0))

        return (0..<rows).map { row in
            (0..<7).compactMap { col in
                cal.date(byAdding: .day, value: row * 7 + col, to: start)
            }
        }
    }
}
