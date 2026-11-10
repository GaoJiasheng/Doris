import SwiftUI
import DorisCore
import DorisUI

/// The "Stats" main-window tab: tokens, meeting time and typing, across all
/// devices or for any one (`ActivityOverview`, over the synced `ActivityDay`
/// rows), then the state of this Mac's token sources.
struct MainTokensView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Binding var metric: ActivityMetric

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ActivityOverview(metric: $metric, localDeviceKey: ActivityDevice.key, title: L("Stats", "统计"))
                if TokenStore.shared != nil {
                    TokenSourcesSection()
                } else {
                    unavailable
                }
            }
            .padding(20)
        }
    }

    private var unavailable: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.slash").foregroundStyle(.secondary)
            Text(L("Token monitoring unavailable", "Token 监控不可用"))
                .font(.headline).foregroundStyle(.secondary)
        }
    }
}

/// Where this Mac's token numbers come from, and a way to rescan.
private struct TokenSourcesSection: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var settings = TokenMonitorSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            sourcesCard
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text(L("Token sources · this Mac", "Token 数据源 · 本机"))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
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

    // MARK: Source status (all five tools; unimplemented shown as coming)

    private var sourcesCard: some View {
        CyberCard {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 18)], spacing: 10) {
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

}
