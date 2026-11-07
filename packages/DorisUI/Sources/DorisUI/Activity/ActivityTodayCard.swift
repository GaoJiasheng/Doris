import SwiftUI
import DorisCore

/// The iPhone Today screen's glance at what your Macs recorded: today's
/// number for each metric and the week's shape. Tapping it opens the full
/// Stats page; the card itself has no chevron row so it stays one line tall.
public struct ActivityTodayCard: View {
    let totals: [String: ActivityTotal]

    public init(totals: [String: ActivityTotal]) {
        self.totals = totals
    }

    public var body: some View {
        let today = ActivityTotals.summary(totals).today
        let week = ActivityTotals.series(totals, days: 7)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 0) {
            ForEach(Array(ActivityMetric.allCases.enumerated()), id: \.element) { i, m in
                if i > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 0.5)
                        .padding(.vertical, 4)
                }
                column(m, value: m.value(today), bars: week.map { m.value($0.total) })
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(shape.fill(.regularMaterial))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .contentShape(shape)
    }

    private func column(_ m: ActivityMetric, value: Int, bars: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(m.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: m.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(m.color)
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            Text(m.compactLong(value))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ActivityMiniBars(values: bars, color: m.color)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}
