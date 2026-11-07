import SwiftUI
import DorisCore

/// The card that appears when you hover the notch numbers: all three metrics
/// for today, the last 7 days and the daily average, with the week's shape.
/// Always dark, since it hangs off a black tab.
public struct ActivityHoverCard: View {
    let totals: [String: ActivityTotal]

    public init(totals: [String: ActivityTotal]) {
        self.totals = totals
    }

    public var body: some View {
        let s = ActivityTotals.summary(totals)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    columnTitle(L("Today", "今日"))
                    columnTitle(L("7 days", "7 天"))
                    columnTitle(L("Daily", "日均"))
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                ForEach(ActivityMetric.allCases) { m in
                    GridRow {
                        Label {
                            Text(m.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                        } icon: {
                            Image(systemName: m.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(m.color)
                                .frame(width: 14)
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.leading)
                        Text(m.compactLong(m.value(s.today)))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        secondary(m.compactLong(m.value(s.week)))
                        secondary(m.compact(m.value(s.average)))
                        ActivityMiniBars(values: ActivityTotals.series(totals, days: 7).map { m.value($0.total) },
                                         color: m.color)
                            .frame(width: 40, height: 16)
                    }
                    .monospacedDigit()
                }
            }
            Text(L("All your devices · click for Stats", "全部设备合计 · 点击查看统计"))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fixedSize()
        .background(shape.fill(Color(white: 0.07)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.11), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
    }

    private func columnTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
    }

    private func secondary(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
    }
}
