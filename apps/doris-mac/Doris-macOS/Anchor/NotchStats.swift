import AppKit
import SwiftUI
import SwiftData
import Combine
import DorisCore
import DorisUI

// MARK: - Settings

/// Which activity numbers the notch logo shows, and where.
@MainActor
final class NotchStatsSettings: ObservableObject {
    static let shared = NotchStatsSettings()

    /// Where the numbers sit relative to the logo; `end` puts the cat first.
    /// Along a side edge "start" is above and "end" below.
    enum Placement: String, CaseIterable, Identifiable {
        case start, end, split
        var id: String { rawValue }
    }

    enum Range: String, CaseIterable, Identifiable {
        case today, week
        var id: String { rawValue }
    }

    /// Shown metrics, in order. Empty = off.
    @Published var metrics: [ActivityMetric] { didSet { save() } }
    @Published var placement: Placement { didSet { save() } }
    @Published var range: Range { didSet { save() } }

    private let defaults = UserDefaults.standard
    private static let metricsKey = "doris.notchStats.metrics"
    private static let placementKey = "doris.notchStats.numbersSide"
    private static let rangeKey = "doris.notchStats.range"

    private init() {
        if let raw = defaults.array(forKey: Self.metricsKey) as? [String] {
            metrics = raw.compactMap(ActivityMetric.init(rawValue:))
        } else {
            metrics = [.tokens, .words]
        }
        placement = Placement(rawValue: defaults.string(forKey: Self.placementKey) ?? "") ?? .end
        range = Range(rawValue: defaults.string(forKey: Self.rangeKey) ?? "") ?? .today
    }

    private func save() {
        defaults.set(metrics.map(\.rawValue), forKey: Self.metricsKey)
        defaults.set(placement.rawValue, forKey: Self.placementKey)
        defaults.set(range.rawValue, forKey: Self.rangeKey)
    }

    /// The metrics for the logo's start side and end side.
    var sides: (start: [ActivityMetric], end: [ActivityMetric]) {
        switch placement {
        case .start: return (metrics, [])
        case .end:   return ([], metrics)
        case .split:
            let n = (metrics.count + 1) / 2
            return (Array(metrics.prefix(n)), Array(metrics.dropFirst(n)))
        }
    }
}

// MARK: - Tab shape with per-corner rounding

/// Which corners of a notch-side tab are rounded. The joins between the
/// logo, the focus pip and the number tabs stay square so the pieces read
/// as one black shape.
struct TabCorners: Equatable {
    var topLeft = false, topRight = false, bottomLeft = false, bottomRight = false
}

/// Rectangle with quad-curve rounding on the chosen corners — the same
/// curve as `NotchExtensionShape` and friends.
struct TabShape: Shape {
    var corners: TabCorners
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        var p = Path()
        // SwiftUI's y grows downward: minY is the top edge.
        p.move(to: CGPoint(x: rect.minX + (corners.topLeft ? r : 0), y: rect.minY))
        if corners.topRight {
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        if corners.bottomRight {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        if corners.bottomLeft {
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        if corners.topLeft {
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Window

/// One black tab of activity numbers docked beside the logo (or the focus
/// pip). `AnchorController` owns two — the start and end side — and lays
/// them out from the logo's frame and shape.
@MainActor
final class NotchStatsWindow {
    let model = NotchStatsModel()
    private let window: NSWindow

    /// Fixed footprint per number so the tab doesn't jitter as digits change.
    static let slotWidth: CGFloat = 54
    static let slotHeight: CGFloat = 30
    static let padding: CGFloat = 8
    /// On a side edge, padding on the side facing the cat, so the gap to the
    /// cat matches the gap between numbers.
    static let verticalCatPadding: CGFloat = 2
    /// Beside a real notch, numbers stack two to a column to save menu-bar width.
    static let stackedSlotWidth: CGFloat = 42
    static let stackedPadding: CGFloat = 4
    static let stackedColumnGap: CGFloat = 6

    /// Left click → that number's Stats tab in the popup; right click → the
    /// cat's menu (built by the caller), told which number was clicked.
    init(container: ModelContainer,
         onClick: @escaping (ActivityMetric) -> Void,
         onRightClick: @escaping (ActivityMetric) -> Void) {
        let win = ClickWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 32),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        win.isReleasedWhenClosed = false
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.isMovable = false
        win.hidesOnDeactivate = false
        // Always a black tab, so the metric colors use their dark-mode shades
        // even when the Mac is in light mode.
        win.appearance = NSAppearance(named: .darkAqua)
        window = win
        win.onClick = { [weak self] point in
            if let self { onClick(self.metric(at: point)) }
        }
        win.onRightClick = { [weak self] point in
            if let self { onRightClick(self.metric(at: point)) }
        }

        let host = NSHostingController(rootView: NotchStatsView(model: model).modelContainer(container))
        // The frame comes from the logo's; content must never resize the window.
        host.sizingOptions = []
        host.view.wantsLayer = true
        win.contentViewController = host

        let tracker = HoverTrackingView(frame: host.view.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.cardProvider = { NotchStatsTip.card(container: container) }
        tracker.anchorProvider = { [weak self] in self?.pillFrame ?? win.frame }
        host.view.addSubview(tracker)
    }

    /// Length along the edge for `n` numbers (horizontal width or vertical height).
    static func length(_ n: Int, vertical: Bool) -> CGFloat {
        guard n > 0 else { return 0 }
        let slot = vertical ? slotHeight : slotWidth
        return padding + (vertical ? verticalCatPadding : padding) + CGFloat(n) * slot + CGFloat(n - 1) * (vertical ? 2 : 4)
    }

    /// Width for `n` numbers stacked two to a column.
    static func stackedLength(_ n: Int) -> CGFloat {
        guard n > 0 else { return 0 }
        let columns = CGFloat((n + 1) / 2)
        return stackedPadding * 2 + columns * stackedSlotWidth + (columns - 1) * stackedColumnGap
    }

    func show(frame: NSRect) {
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() { window.orderOut(nil) }
    var isVisible: Bool { window.isVisible }
    var frame: NSRect { window.frame }

    /// The whole logo-and-numbers shape; the hover card centres under it.
    var pillFrame: NSRect = .zero

    /// The number nearest a click, so the gaps between numbers aren't dead.
    /// `point` is in window coordinates (origin bottom-left).
    private func metric(at point: NSPoint) -> ActivityMetric {
        let p = CGPoint(x: point.x, y: window.frame.height - point.y)
        func distance(_ r: CGRect) -> CGFloat {
            hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
        }
        let nearest = model.metrics
            .compactMap { m in model.cellFrames[m].map { (m, distance($0)) } }
            .min { $0.1 < $1.1 }
        return nearest?.0 ?? model.metrics.first ?? .tokens
    }

    /// Takes the clicks itself and reports where they landed, so the caller
    /// knows which number was clicked.
    private final class ClickWindow: NSWindow {
        var onClick: (NSPoint) -> Void = { _ in }
        var onRightClick: (NSPoint) -> Void = { _ in }

        override func sendEvent(_ event: NSEvent) {
            switch event.type {
            case .leftMouseUp:
                HoverTipWindow.shared.cancel()
                onClick(event.locationInWindow)
            case .rightMouseDown:
                HoverTipWindow.shared.cancel()
                onRightClick(event.locationInWindow)
            case .leftMouseDown, .rightMouseUp:
                break
            default:
                super.sendEvent(event)
            }
        }
    }
}

@MainActor
final class NotchStatsModel: ObservableObject {
    @Published var metrics: [ActivityMetric] = []
    @Published var vertical = false
    @Published var stacked = false
    @Published var corners = TabCorners()
    /// Extra room on one side that pokes into the camera notch (not drawn on).
    @Published var inset = EdgeInsets()
    /// Where each number is drawn (window coordinates, origin top-left).
    var cellFrames: [ActivityMetric: CGRect] = [:]
}

private struct CellFramesKey: PreferenceKey {
    static var defaultValue: [ActivityMetric: CGRect] = [:]
    static func reduce(value: inout [ActivityMetric: CGRect], nextValue: () -> [ActivityMetric: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct NotchStatsView: View {
    @ObservedObject var model: NotchStatsModel
    @ObservedObject private var settings = NotchStatsSettings.shared
    @Query private var rows: [ActivityDay]

    init(model: NotchStatsModel) {
        self.model = model
        // Only the last week matters here.
        let cutoff = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? .distantPast
        _rows = Query(filter: #Predicate<ActivityDay> { $0.dayStart >= cutoff })
    }

    var body: some View {
        // Re-evaluate at least once a minute so "today" rolls over at midnight.
        TimelineView(.everyMinute) { _ in
            let summary = ActivityTotals.summary(ActivityTotals.byDay(rows.map(ActivityRecord.init)))
            let totals = settings.range == .today ? summary.today : summary.week
            ZStack {
                TabShape(corners: model.corners).fill(Color.black)
                Group {
                    if model.stacked {
                        stackedColumns(totals)
                    } else {
                        stack {
                            ForEach(model.metrics) { m in
                                cell(m, m.compact(m.value(totals)))
                                    .background(frameReporter(m))
                            }
                        }
                    }
                }
                .padding(model.inset)
            }
        }
        // Clicks are handled by the window (NotchStatsWindow.ClickWindow),
        // which uses these frames to tell which number was hit.
        .onPreferenceChange(CellFramesKey.self) { model.cellFrames = $0 }
    }

    private func frameReporter(_ m: ActivityMetric) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: CellFramesKey.self, value: [m: geo.frame(in: .global)])
        }
    }

    /// Two numbers to a column, icons lined up down the column.
    private func stackedColumns(_ totals: ActivityTotal) -> some View {
        let columns = stride(from: 0, to: model.metrics.count, by: 2).map {
            Array(model.metrics[$0..<min($0 + 2, model.metrics.count)])
        }
        return HStack(spacing: NotchStatsWindow.stackedColumnGap) {
            ForEach(columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(column) { m in
                        HStack(spacing: 3) {
                            Image(systemName: m.symbol)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(m.color)
                                .frame(width: 12)
                            Text(m.compact(m.value(totals)))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        // A lone number centres in its tab; a pair keeps its icons in line.
                        .frame(width: column.count > 1 ? NotchStatsWindow.stackedSlotWidth : nil, alignment: .leading)
                        .background(frameReporter(m))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stack<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if model.vertical {
            VStack(spacing: 2) { content() }
        } else {
            HStack(spacing: 4) { content() }
        }
    }

    @ViewBuilder
    private func cell(_ m: ActivityMetric, _ text: String) -> some View {
        let icon = Image(systemName: m.symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(m.color)
        let number = Text(text)
            .font(.system(size: model.vertical ? 10 : 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        if model.vertical {
            VStack(spacing: 1) { icon; number }
                .frame(height: NotchStatsWindow.slotHeight)
        } else {
            HStack(spacing: 4) { icon; number }
                .frame(width: NotchStatsWindow.slotWidth)
        }
    }
}

/// Hover card: today / last 7 days / daily average for all three metrics,
/// whichever number the pointer is on.
@MainActor
enum NotchStatsTip {
    static func card(container: ModelContainer) -> AnyView? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? .distantPast
        let rows = (try? ModelContext(container).fetch(FetchDescriptor<ActivityDay>(
            predicate: #Predicate { $0.dayStart >= cutoff }))) ?? []
        return AnyView(ActivityHoverCard(totals: ActivityTotals.byDay(rows.map(ActivityRecord.init))))
    }
}

/// What a click on the notch's cat or numbers opens.
enum NotchPage: Equatable {
    case tasks
    case stats(ActivityMetric)
}

extension Notification.Name {
    /// Switch a window to a `NotchPage`. `object` is the window's id
    /// (`MainWindowController.windowID`); `userInfo["page"]` the page.
    static let dorisShowPage = Notification.Name("doris.showPage")
}

// MARK: - Settings section

/// "Notch numbers" in Settings: which numbers, their order, the side and the range.
struct NotchStatsSettingsSection: View {
    @ObservedObject private var settings = NotchStatsSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Stats and notch numbers", "统计与刘海数字"))
                .font(.headline)
                .foregroundStyle(.primary)

            TypingAccessRow()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ordered) { m in
                    row(m)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L("Cat position", "小猫位置")).font(.subheadline)
                Picker("", selection: $settings.placement) {
                    Text(L("Left", "左边")).tag(NotchStatsSettings.Placement.end)
                    Text(L("Middle", "中间")).tag(NotchStatsSettings.Placement.split)
                    Text(L("Right", "右边")).tag(NotchStatsSettings.Placement.start)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L("Numbers for", "数字范围")).font(.subheadline)
                Picker("", selection: $settings.range) {
                    Text(L("Today", "今日")).tag(NotchStatsSettings.Range.today)
                    Text(L("Last 7 days", "近 7 日")).tag(NotchStatsSettings.Range.week)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Text(L("Numbers are summed across your devices. Beside a MacBook notch each side takes only the room it needs; elsewhere the whole shape stays centred. On a left or right screen edge, left means top and right bottom. Hover it for today, 7 days and the daily average.",
                   "数字是你所有设备的合计。在 MacBook 刘海两侧，左右各占需要的宽度；其他位置数字和小猫整体居中。贴在屏幕左右两侧时，「左边」在上、「右边」在下。鼠标移上去可以看今日、7 天和日均。"))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown metrics in their order, then the hidden ones.
    private var ordered: [ActivityMetric] {
        settings.metrics + ActivityMetric.allCases.filter { !settings.metrics.contains($0) }
    }

    private func row(_ m: ActivityMetric) -> some View {
        let on = settings.metrics.contains(m)
        let index = settings.metrics.firstIndex(of: m)
        return HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { on }, set: { show in
                if show { settings.metrics.append(m) } else { settings.metrics.removeAll { $0 == m } }
            })) {
                Label(m.title, systemImage: m.symbol)
                    .foregroundStyle(on ? m.color : .secondary)
            }
            .toggleStyle(.checkbox)
            Spacer()
            if let index, index > 0 {
                Button {
                    settings.metrics.swapAt(index, index - 1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .help(L("Move earlier", "往前移"))
            }
        }
    }
}

// MARK: - Permission row

/// Typing counts need Accessibility (the same switch voice input uses).
struct TypingAccessRow: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var typing = TypingBridge.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.subheadline)
                Spacer()
                switch typing.state {
                case .off:
                    Button(L("Turn On…", "开启…")) { typing.enable() }
                case .needsAccess, .starting:
                    Button(L("Allow…", "去开启…")) { typing.requestAccess() }
                    Button(L("Turn Off", "关闭")) { typing.disable() }
                case .counting:
                    Button(L("Turn Off", "关闭")) { typing.disable() }
                }
            }
            if typing.state != .counting {
                Text(L("Counting reads what you type in other apps, so it runs in a small helper that needs its own Accessibility switch, listed as “DorisTyping”. If it isn’t there, drag it in from the Finder window. Only word counts reach Doris; the text is never kept.",
                       "统计打字需要读取其他 App 里的文字，所以由一个小助手来做，它需要单独开启「辅助功能」，在列表里显示为「DorisTyping」。如果列表里没有，把 Finder 中选中的它拖进列表。交给 Doris 的只有字数，文字本身不保存。"))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        switch typing.state {
        case .off: L("Typing isn’t counted", "未统计打字字数")
        case .starting: L("Starting the word counter…", "正在启动字数助手…")
        case .needsAccess: L("Turn on “DorisTyping” in Accessibility", "请在「辅助功能」里打开「DorisTyping」")
        case .counting: L("Typing is counted", "正在统计打字字数")
        }
    }

    private var icon: String {
        switch typing.state {
        case .counting: "checkmark.circle.fill"
        case .off: "circle"
        default: "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch typing.state {
        case .counting: .green
        case .off: .secondary
        default: .orange
        }
    }
}
