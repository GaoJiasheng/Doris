import SwiftUI
import SwiftData
import Charts
import DorisCore

/// The Stats page: three metrics, one story at a time. Tabs show today's
/// number and the week's shape; the selected metric fills a colour card with
/// its four ranges and bars, then what it's made of — tools and models for
/// tokens, and devices. Reads across all devices or just one. Shared by the
/// Mac Stats tab and the iPhone's read-only screen; reads the synced
/// `ActivityDay` rows from the main container.
public struct ActivityOverview: View {
    /// This Mac's `deviceKey`, marked "this Mac" in the device lists. Nil on iPhone.
    let localDeviceKey: String?
    /// Page title. Nil where the navigation bar has one.
    let title: String?

    @ObservedObject private var lang = LanguageSettings.shared
    @Query(sort: [SortDescriptor(\ActivityDay.dayStart, order: .reverse)])
    private var rows: [ActivityDay]
    /// The device being looked at; nil = all of them.
    @State private var device: String?
    @Binding private var metric: ActivityMetric
    @State private var period: ActivityPeriod = .week

    public init(metric: Binding<ActivityMetric>, localDeviceKey: String? = nil, title: String? = nil) {
        _metric = metric
        self.localDeviceKey = localDeviceKey
        self.title = title
    }

    public var body: some View {
        let records = rows.map(ActivityRecord.init)
        let devices = ActivityTotals.devices(records)
        // A device that's gone from the list falls back to all of them.
        let scope = devices.contains { $0.key == device } ? device : nil
        let totals = ActivityTotals.byDay(records, deviceKey: scope)

        VStack(alignment: .leading, spacing: 18) {
            header(devices, scope: scope)

            HStack(spacing: 12) {
                ForEach(ActivityMetric.allCases) { m in
                    MetricTab(metric: m, totals: totals, selected: m == metric) {
                        withAnimation(.snappy(duration: 0.25)) { metric = m }
                    }
                }
            }

            ActivityHeroCard(metric: metric, totals: totals, period: $period)

            if metric == .tokens {
                TokenBreakdown(detail: ActivityTotals.tokenDetail(records, period, deviceKey: scope), period: period)
            }

            if devices.count > 1, scope == nil {
                DeviceBreakdown(metric: metric, period: period, records: records, devices: devices,
                                localDeviceKey: localDeviceKey) { key in
                    withAnimation(.snappy(duration: 0.25)) { device = key }
                }
            }
        }
    }

    @ViewBuilder
    private func header(_ devices: [(key: String, name: String)], scope: String?) -> some View {
        let filter = DeviceFilter(devices: devices, localDeviceKey: localDeviceKey, selection: scope) { key in
            withAnimation(.snappy(duration: 0.25)) { device = key }
        }
        if let title {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    titleBlock(title).fixedSize()
                    Spacer(minLength: 12)
                    if devices.count > 1 { filter.fixedSize() }
                }
                VStack(alignment: .leading, spacing: 10) {
                    titleBlock(title)
                    if devices.count > 1 { filter }
                }
            }
        } else if devices.count > 1 {
            filter
        }
    }

    private func titleBlock(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text(Self.dateLine(chinese: lang.mode == .chinese))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private static func dateLine(chinese: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        f.dateFormat = chinese ? "M月d日 EEEE" : "EEEE, MMM d"
        return f.string(from: Date())
    }
}

// MARK: - Device filter

/// All devices, or one. Only shown once there's more than one to tell apart.
private struct DeviceFilter: View {
    let devices: [(key: String, name: String)]
    let localDeviceKey: String?
    let selection: String?
    let select: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                chip(L("All devices", "全部设备"), key: nil)
                // This Mac first, then the rest.
                ForEach(devices.sorted { a, _ in a.key == localDeviceKey }, id: \.key) { d in
                    chip(d.name.isEmpty ? "Mac" : d.name, key: d.key, mine: d.key == localDeviceKey)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
    }

    private func chip(_ name: String, key: String?, mine: Bool = false) -> some View {
        let selected = key == selection
        return Button { select(key) } label: {
            HStack(spacing: 4) {
                Text(name).lineLimit(1)
                if mine {
                    Text(L("this Mac", "本机"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if selected { Capsule().fill(Color.primary.opacity(0.1)) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Metric tab

/// A metric's name, today's number and the week's shape.
private struct MetricTab: View {
    let metric: ActivityMetric
    let totals: [String: ActivityTotal]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let m = metric
        let today = ActivityTotals.total(totals, .today)
        let week = ActivityTotals.series(totals, days: 7).map { m.value($0.total) }
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: m.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(m.heroGradient))
                    Text(m.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
                // Where a tab is too narrow for both, the number wins.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        figure(today).fixedSize()
                        Spacer(minLength: 0)
                        ActivityMiniBars(values: week, color: m.color)
                            .frame(width: 52, height: 26)
                            .opacity(selected ? 1 : 0.6)
                    }
                    figure(today)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func figure(_ today: ActivityTotal) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(metric.compactLong(metric.value(today)))
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(L("today", "今日"))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return CyberCard(cornerRadius: 18) { Color.clear }
            .overlay {
                if selected {
                    shape.fill(metric.heroGradient).opacity(0.1)
                    shape.strokeBorder(metric.heroGradient, lineWidth: 1.5)
                }
            }
    }
}

// MARK: - Mini bars

/// Seven tiny bars: a range's shape at a glance. The last bar (today) is solid.
public struct ActivityMiniBars: View {
    let values: [Int]
    let color: Color

    public init(values: [Int], color: Color) {
        self.values = values
        self.color = color
    }

    public var body: some View {
        let top = max(1, values.max() ?? 1)
        GeometryReader { geo in
            let gap: CGFloat = 2
            let count = max(1, values.count)
            let w = max(1, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: min(1.5, w / 2), style: .continuous)
                        .fill(color.opacity(i == count - 1 ? 1 : 0.42))
                        .frame(width: w, height: max(2, geo.size.height * CGFloat(v) / CGFloat(top)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }
}

// MARK: - Hero card

/// The selected metric, on its own colour: the number for the chosen range,
/// the four ranges to choose from, and the bars.
private struct ActivityHeroCard: View {
    let metric: ActivityMetric
    let totals: [String: ActivityTotal]
    @Binding var period: ActivityPeriod

    var body: some View {
        let t = ActivityTotals.total(totals, period)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    headline(t)
                    Spacer(minLength: 0)
                    strip.frame(maxWidth: 400)
                }
                VStack(alignment: .leading, spacing: 16) {
                    headline(t)
                    strip
                }
            }
            ActivityBarChart(metric: metric, totals: totals, period: period)
        }
        .padding(22)
        .background {
            shape.fill(metric.heroGradient)
            // A soft light from the top corner, so the colour has some depth.
            shape.fill(RadialGradient(colors: [.white.opacity(0.13), .clear],
                                      center: .topTrailing, startRadius: 0, endRadius: 460))
        }
        .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: metric.heroShadow.opacity(0.3), radius: 22, y: 12)
        .environment(\.colorScheme, .dark)
    }

    private func headline(_ t: ActivityTotal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(period.longTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Text(metric.full(metric.value(t)))
                .font(.system(size: 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
            Text(caption(t))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Daily average (yesterday, for today), then the cost for tokens.
    private func caption(_ t: ActivityTotal) -> String {
        var parts: [String] = []
        if period == .today {
            let yesterday = ActivityTotals.series(totals, days: 2).first.map { metric.compact(metric.value($0.total)) } ?? "0"
            parts.append(L("Yesterday \(yesterday)", "昨日 \(yesterday)"))
        } else {
            // All time counts from this metric's own first day: typing has
            // only just started while token history goes back months.
            let own = totals.filter { metric.value($0.value) > 0 }
            let avg = metric.value(t) / ActivityTotals.dayCount(own, period)
            parts.append(L("\(metric.compact(avg)) a day", "日均 \(metric.compact(avg))"))
        }
        if metric == .tokens, t.tokenCostUSD > 0 {
            parts.append(L("about \(ActivityFormat.usdFull(t.tokenCostUSD))", "约 \(ActivityFormat.usdFull(t.tokenCostUSD))"))
        }
        return parts.joined(separator: " · ")
    }

    private var strip: some View {
        HStack(spacing: 3) {
            ForEach(ActivityPeriod.allCases) { p in
                let selected = p == period
                Button {
                    withAnimation(.snappy(duration: 0.25)) { period = p }
                } label: {
                    VStack(spacing: 2) {
                        Text(p.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? metric.heroInk.opacity(0.8) : .white.opacity(0.75))
                        Text(metric.compactLong(metric.value(ActivityTotals.total(totals, p))))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(selected ? metric.heroInk : .white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(minWidth: 56)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 2)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white.opacity(0.16))
        )
    }
}

// MARK: - Bar chart

/// White bars on the hero's colour; today and the hovered bar stand out.
private struct ActivityBarChart: View {
    let metric: ActivityMetric
    let totals: [String: ActivityTotal]
    let period: ActivityPeriod
    @State private var hovered: Date?

    private struct Bar: Identifiable {
        let start: Date
        let raw: Int
        let plotted: Double
        var id: Date { start }
    }

    var body: some View {
        let data = ActivityTotals.bars(totals.filter { metric.value($0.value) > 0 }, period)
        let unit: Calendar.Component = data.byMonth ? .month : .day
        let top = data.points.map { metric.value($0.total) }.max() ?? 0
        let scale = AxisScale(metric: metric, top: top)
        let bars = data.points.map { Bar(start: $0.start, raw: metric.value($0.total), plotted: scale.plot(metric.value($0.total))) }
        let cal = Calendar.current
        let picked = hovered.flatMap { h in bars.first { cal.isDate($0.start, equalTo: h, toGranularity: unit) } }
        // The average of the bars drawn.
        let average = bars.isEmpty || data.byMonth ? 0 : bars.reduce(0) { $0 + $1.raw } / bars.count

        if top == 0 {
            emptyState
        } else {
            chart(bars, unit: unit, byMonth: data.byMonth, scale: scale, picked: picked, average: average)
                .frame(height: 200)
        }
    }

    private func chart(_ bars: [Bar], unit: Calendar.Component, byMonth: Bool, scale: AxisScale,
                       picked: Bar?, average: Int) -> some View {
        Chart {
            ForEach(bars) { b in
                BarMark(x: .value("Day", b.start, unit: unit),
                        y: .value(metric.title, b.plotted),
                        width: .ratio(bars.count > 20 ? 0.68 : 0.46))
                    .cornerRadius(bars.count > 20 ? 2.5 : 7)
                    .foregroundStyle(.white.opacity(opacity(b, unit: unit, picked: picked)))
            }
            if average > 0, picked == nil {
                RuleMark(y: .value("Average", scale.plot(average)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .foregroundStyle(.white.opacity(0.7))
                    .annotation(position: .top, alignment: .leading, spacing: 3) {
                        Text(L("avg \(metric.compact(average))", "日均 \(metric.compact(average))"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
            }
            if let picked {
                RuleMark(x: .value("Day", picked.start, unit: unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 2,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        bubble(picked, byMonth: byMonth)
                    }
            }
        }
        .chartYScale(domain: 0...max(scale.plot(bars.map(\.raw).max() ?? 0) * 1.08, 0.001))
        .chartXAxis {
            AxisMarks(values: ticks(bars, unit: unit)) { value in
                AxisValueLabel(collisionResolution: .disabled) {
                    if let d = value.as(Date.self) {
                        Text(tickLabel(d, byMonth: byMonth))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.16))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(scale.label(v))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
        }
        #if os(macOS)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            guard let plot = proxy.plotFrame else { return }
                            hovered = proxy.value(atX: p.x - geo[plot].minX, as: Date.self)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        #else
        .chartXSelection(value: $hovered)
        #endif
        .animation(.snappy(duration: 0.25), value: bars.map(\.raw))
    }

    private func opacity(_ b: Bar, unit: Calendar.Component, picked: Bar?) -> Double {
        let cal = Calendar.current
        if let picked { return picked.start == b.start ? 1 : 0.32 }
        let isNow = cal.isDate(b.start, equalTo: Date(), toGranularity: unit)
        if period == .today { return isNow ? 1 : 0.32 }
        return isNow ? 1 : 0.62
    }

    private func bubble(_ b: Bar, byMonth: Bool) -> some View {
        VStack(spacing: 1) {
            Text(longLabel(b.start, byMonth: byMonth))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(metric.heroInk.opacity(0.7))
            Text(metric.full(b.raw))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(metric.heroInk)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
    }

    /// Mid-bar positions for the axis labels; about seven of them.
    private func ticks(_ bars: [Bar], unit: Calendar.Component) -> [Date] {
        let every = max(1, Int((Double(bars.count) / 7).rounded(.up)))
        let cal = Calendar.current
        let reversed = Array(bars.reversed())
        return stride(from: 0, to: reversed.count, by: every).map { reversed[$0].start }.map { start in
            let hours = unit == .month ? 24 * 14 : 12
            return cal.date(byAdding: .hour, value: hours, to: start) ?? start
        }
    }

    private func tickLabel(_ d: Date, byMonth: Bool) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        if byMonth { return "\(c.month ?? 0)" + L("", "月") }
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    private func longLabel(_ d: Date, byMonth: Bool) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        if byMonth { return "\(c.year ?? 0)/\(c.month ?? 0)" }
        if Calendar.current.isDateInToday(d) { return L("Today", "今日") }
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: metric.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(emptyMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var emptyMessage: String {
        switch metric {
        case .tokens:  return L("No token use in this range.", "这段时间没有 Token 用量。")
        case .meeting: return L("Meetings in Feishu / Lark, Zoom, Tencent Meeting or DingTalk show up here on their own.",
                                 "在飞书 / Lark、Zoom、腾讯会议或钉钉开会时，时长会自动记到这里。")
        case .words:   return L("What you type or dictate is counted here.", "打字和语音输入的字数会记到这里。")
        }
    }
}

/// How a metric's values are plotted and labelled. Meeting time plots in
/// hours or minutes so the axis lands on round numbers, not round seconds.
private struct AxisScale {
    let metric: ActivityMetric
    let divisor: Double
    let suffix: String

    init(metric: ActivityMetric, top: Int) {
        self.metric = metric
        if metric == .meeting {
            if top >= 3600 { divisor = 3600; suffix = "h" } else { divisor = 60; suffix = "m" }
        } else {
            divisor = 1; suffix = ""
        }
    }

    func plot(_ v: Int) -> Double { Double(v) / divisor }

    func label(_ v: Double) -> String {
        if metric == .meeting {
            let text = v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
            return v == 0 ? "0" : text + suffix
        }
        return metric.compact(Int(v))
    }
}

// MARK: - Breakdowns

private struct TokenBreakdown: View {
    let detail: [TokenDetailEntry]
    let period: ActivityPeriod

    private var ramp: [Color] { ActivityMetric.tokens.ramp }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                tools.frame(minWidth: 340)
                models.frame(minWidth: 340)
            }
            // Both cards as tall as the taller one.
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                tools
                models
            }
        }
    }

    private struct Part: Identifiable {
        let id: String
        let tokens: Int
        let cost: Double
    }

    private func grouped(by key: (TokenDetailEntry) -> String) -> [Part] {
        Dictionary(grouping: detail.filter { $0.tokens > 0 }, by: key)
            .map { Part(id: $0.key, tokens: $0.value.reduce(0) { $0 + $1.tokens }, cost: $0.value.reduce(0) { $0 + $1.cost }) }
            .sorted { $0.tokens > $1.tokens }
    }

    private func color(_ i: Int) -> Color { ramp[min(i, ramp.count - 1)] }

    // Tools: a ring, because they're few and the split is the point.

    private var tools: some View {
        let parts = grouped(by: \.tool)
        let total = parts.reduce(0) { $0 + $1.tokens }
        return BreakdownCard(title: L("By tool", "按工具"), period: period, isEmpty: parts.isEmpty) {
            HStack(spacing: 18) {
                ZStack {
                    Chart(Array(parts.enumerated()), id: \.element.id) { i, p in
                        SectorMark(angle: .value("Tokens", p.tokens), innerRadius: .ratio(0.7), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(color(i))
                    }
                    VStack(spacing: 0) {
                        Text(ActivityFormat.count(total))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(L("total", "合计"))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(width: 104, height: 104)

                VStack(spacing: 11) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { i, p in
                        HStack(spacing: 8) {
                            Circle().fill(color(i)).frame(width: 8, height: 8)
                            Text(p.id)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(ActivityFormat.count(p.tokens))
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                Text(ActivityFormat.usd(p.cost))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // Models: ranked bars, because there are many and the order is the point.

    private var models: some View {
        var parts = grouped(by: \.model)
        if parts.count > 5 {
            let rest = parts[4...]
            parts = Array(parts[..<4]) + [Part(id: L("\(rest.count) others", "其他 \(rest.count) 个"),
                                               tokens: rest.reduce(0) { $0 + $1.tokens },
                                               cost: rest.reduce(0) { $0 + $1.cost })]
        }
        let top = max(1, parts.map(\.tokens).max() ?? 1)
        return BreakdownCard(title: L("By model", "按模型"), period: period, isEmpty: parts.isEmpty) {
            VStack(spacing: 11) {
                ForEach(Array(parts.enumerated()), id: \.element.id) { i, p in
                    RankedRow(name: p.id, value: ActivityFormat.count(p.tokens), detail: ActivityFormat.usd(p.cost),
                              fraction: CGFloat(p.tokens) / CGFloat(top), color: color(i), monospaced: true)
                }
            }
        }
    }
}

private struct DeviceBreakdown: View {
    let metric: ActivityMetric
    let period: ActivityPeriod
    let records: [ActivityRecord]
    let devices: [(key: String, name: String)]
    let localDeviceKey: String?
    let select: (String) -> Void

    var body: some View {
        let parts = devices.map { d in
            (key: d.key, name: d.name.isEmpty ? "Mac" : d.name,
             value: metric.value(ActivityTotals.total(ActivityTotals.byDay(records, deviceKey: d.key), period)))
        }
        .sorted { $0.value > $1.value }
        let top = max(1, parts.first?.value ?? 1)
        BreakdownCard(title: L("By device", "按设备"), period: period, isEmpty: false) {
            VStack(spacing: 11) {
                ForEach(Array(parts.enumerated()), id: \.element.key) { i, d in
                    Button { select(d.key) } label: {
                        RankedRow(name: d.name, tag: d.key == localDeviceKey ? L("this Mac", "本机") : nil,
                                  value: metric.compactLong(d.value), detail: nil,
                                  fraction: CGFloat(d.value) / CGFloat(top),
                                  color: metric.ramp[min(i, metric.ramp.count - 1)])
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BreakdownCard<Content: View>: View {
    let title: String
    let period: ActivityPeriod
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        CyberCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(period.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                if isEmpty {
                    Text(L("Nothing in this range.", "这段时间没有数据。"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    content()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A name and value over a bar scaled to the largest in the list.
private struct RankedRow: View {
    let name: String
    var tag: String?
    let value: String
    let detail: String?
    let fraction: CGFloat
    let color: Color
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(name)
                    .font(monospaced ? .system(size: 11, weight: .medium, design: .monospaced)
                                     : .system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1).truncationMode(.middle)
                if let tag {
                    Text(tag)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 54, alignment: .trailing)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(color).frame(width: max(5, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Period names

extension ActivityPeriod {
    @MainActor var title: String {
        switch self {
        case .today: return L("Today", "今日")
        case .week:  return L("7 days", "7 天")
        case .month: return L("30 days", "30 天")
        case .all:   return L("All", "全部")
        }
    }

    @MainActor var longTitle: String {
        switch self {
        case .today: return L("Today", "今日")
        case .week:  return L("Last 7 days", "近 7 天")
        case .month: return L("Last 30 days", "近 30 天")
        case .all:   return L("All time", "全部")
        }
    }
}
