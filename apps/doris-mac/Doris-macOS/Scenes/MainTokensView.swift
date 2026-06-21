import SwiftUI
import SwiftData
import Charts
import DorisCore
import DorisUI

/// The "Tokens" main-window tab — a dashboard over the dedicated TokenStore.
/// Outer view injects that container so the inner `@Query` binds to it.
struct MainTokensView: View {
    var body: some View {
        if let container = TokenStore.shared {
            MainTokensInner().modelContainer(container)
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(L("Token monitoring unavailable", "Token 监控不可用"))
                .font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MainTokensInner: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var settings = TokenMonitorSettings.shared
    @Query(sort: [SortDescriptor(\TokenUsageDaily.day, order: .reverse)])
    private var dailies: [TokenUsageDaily]
    @State private var range: TokenStats.Range = .last7
    @StateObject private var quota = QuotaModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerRow
                quotaCard
                statTiles
                trendCard
                rangePicker
                byToolCard
                byModelCard
                sourcesCard
            }
            .padding(20)
        }
        .onAppear { quota.start() }
        .onDisappear { quota.stop() }
    }

    // MARK: Subscription quota (Codex real, Claude estimated)

    private var quotaCard: some View {
        CyberCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle(L("Subscription quota", "订阅额度"))
                if quota.windows.isEmpty {
                    Text(L("No quota signal (open a Codex/Claude session, then Rescan).",
                           "暂无额度信号(跑一段 Codex/Claude 会话后重新扫描)。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(quota.windows) { w in quotaRow(w) }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func quotaRow(_ w: QuotaWindow) -> some View {
        let used = w.usedPercent ?? 0
        let barColor: Color = used >= 90 ? CyberPalette.neonPink
                            : used >= 70 ? .orange : CyberPalette.neonCyan
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: TokenTool(rawValue: w.toolRaw)?.sfSymbol ?? "bolt")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(barColor)
                Text("\(w.toolName) · \(w.label)").font(.system(size: 12, weight: .medium))
                if w.isEstimate {
                    Text(L("est.", "估算"))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                if let plan = w.planType {
                    Text(plan).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                if let rem = w.remainingPercent {
                    Text(String(format: L("%.0f%% left", "剩 %.0f%%"), rem))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(barColor).monospacedDigit()
                } else if let used = w.usedTokens {
                    Text(L("\(TokenFormat.tokens(used)) used", "已用 \(TokenFormat.tokens(used))"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if w.usedPercent != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                        Capsule().fill(barColor).frame(width: geo.size.width * CGFloat(used / 100), height: 6)
                    }
                }
                .frame(height: 6)
            }
            if let reset = w.resetsAt {
                Text(L("resets ", "重置于 ") + reset.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text(L("Token usage", "Token 用量"))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
            Spacer()
            if let last = settings.lastCollectAt {
                Text(L("updated ", "更新于 ") + last.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                TokenCollectionService.shared.triggerNow()
            } label: {
                Label(L("Rescan", "重新扫描"), systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(CyberPalette.neonCyan)
        }
    }

    // MARK: Headline tiles (today / 7d / 30d / all)

    private var statTiles: some View {
        HStack(spacing: 12) {
            ForEach(TokenStats.Range.allCases, id: \.self) { r in
                let t = TokenStats.totals(dailies, r)
                CyberCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rangeLabel(r))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(TokenFormat.tokens(t.billable))
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text(TokenFormat.usd(t.cost))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CyberPalette.neonPink)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
        }
    }

    // MARK: Trend (30 days)

    private var trendCard: some View {
        let points = TokenStats.trend(dailies, days: 30)
        return CyberCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Last 30 days", "近 30 天"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if points.allSatisfy({ $0.billable == 0 }) {
                    emptyHint
                } else {
                    Chart(points, id: \.day) { p in
                        BarMark(
                            x: .value("Day", p.day, unit: .day),
                            y: .value("Tokens", p.billable)
                        )
                        .foregroundStyle(CyberPalette.neonCyan.gradient)
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let n = value.as(Int.self) { Text(TokenFormat.tokens(n)) }
                            }
                        }
                    }
                    .frame(height: 150)
                }
            }
            .padding(14)
        }
    }

    // MARK: Range picker (drives breakdowns)

    private var rangePicker: some View {
        Picker("", selection: $range) {
            ForEach(TokenStats.Range.allCases, id: \.self) { r in
                Text(rangeLabel(r)).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: By tool

    private var byToolCard: some View {
        let rows = TokenStats.byTool(dailies, range).filter { $0.1.billable > 0 }
        let maxV = max(1, rows.map { $0.1.billable }.max() ?? 1)
        return CyberCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L("By tool", "按工具"))
                if rows.isEmpty { emptyHint }
                ForEach(rows, id: \.0) { tool, t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: tool.sfSymbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CyberPalette.neonCyan)
                            Text(tool.displayName).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(TokenFormat.tokens(t.billable))
                                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(TokenFormat.usd(t.cost))
                                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(CyberPalette.neonCyan.opacity(0.25))
                                .frame(width: geo.size.width * CGFloat(t.billable) / CGFloat(maxV), height: 5)
                        }
                        .frame(height: 5)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: By model

    private var byModelCard: some View {
        let rows = TokenStats.byModel(dailies, range).filter { $0.1.billable > 0 }.prefix(10)
        return CyberCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("By model", "按模型"))
                if rows.isEmpty { emptyHint }
                ForEach(Array(rows), id: \.0) { model, t in
                    HStack(spacing: 8) {
                        Text(model)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(t.calls)")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(TokenFormat.tokens(t.billable))
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                        Text(TokenFormat.usd(t.cost))
                            .font(.system(size: 11)).foregroundStyle(CyberPalette.neonPink).monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: Source status (all five tools; unimplemented shown as coming)

    private var sourcesCard: some View {
        CyberCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(L("Sources", "数据源"))
                ForEach(TokenTool.allCases, id: \.self) { tool in
                    HStack(spacing: 8) {
                        Image(systemName: tool.sfSymbol)
                            .font(.system(size: 11)).frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(tool.displayName).font(.system(size: 12))
                        Spacer()
                        statusBadge(for: tool)
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func statusBadge(for tool: TokenTool) -> some View {
        let (text, color): (String, Color) = {
            guard let adapter = TokenSourceRegistry.adapter(for: tool) else {
                return (L("coming soon", "即将支持"), .secondary)
            }
            if !settings.isEnabled(tool) { return (L("off", "已关闭"), .secondary) }
            switch adapter.status() {
            case .ok:                return (L("connected", "已连接"), CyberPalette.neonCyan)
            case .unavailable:       return (L("no logs", "无日志"), .secondary)
            case .needsConfig(let m): return (m, .orange)
            case .unsupported(let m): return (m, .secondary)
            case .error(let m):      return (m, CyberPalette.neonPink)
            }
        }()
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: Helpers

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
    }
    private var emptyHint: some View {
        Text(L("No data in this range yet.", "该区间暂无数据。"))
            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
    }
    private func rangeLabel(_ r: TokenStats.Range) -> String {
        switch r {
        case .today: return L("Today", "今日")
        case .last7: return L("7 days", "7 天")
        case .last30: return L("30 days", "30 天")
        case .all:   return L("All", "全部")
        }
    }
}

/// Owns quota-window refresh (file read for Codex + event fetch for Claude),
/// off the main actor, on appear + a 30s timer.
@MainActor
final class QuotaModel: ObservableObject {
    @Published var windows: [QuotaWindow] = []
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        let container = TokenStore.shared
        let cap = TokenMonitorSettings.shared.claudeWindowCap
        Task.detached(priority: .utility) {
            let w = QuotaReader.windows(container: container, claudeCap: cap)
            await MainActor.run { self.windows = w }
        }
    }
}
