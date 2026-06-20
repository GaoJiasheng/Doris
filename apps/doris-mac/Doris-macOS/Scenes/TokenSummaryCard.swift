import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// Compact token-usage glance for the Today home. Reads from the dedicated
/// `TokenStore` container (not the main Notes container), so it's wrapped in
/// its own `.modelContainer` and the `@Query` lives in the inner view (the
/// descendant of where the container is applied).
struct TokenSummaryCard: View {
    var onTap: () -> Void = {}

    var body: some View {
        if let container = TokenStore.shared {
            TokenSummaryCardInner(onTap: onTap)
                .modelContainer(container)
        }
    }
}

private struct TokenSummaryCardInner: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @Query(sort: [SortDescriptor(\TokenUsageDaily.day, order: .reverse)])
    private var dailies: [TokenUsageDaily]
    var onTap: () -> Void

    var body: some View {
        let today = TokenStats.totals(dailies, .today)
        let tools = TokenStats.byTool(dailies, .today).filter { $0.1.billable > 0 }

        Button(action: onTap) {
            CyberCard {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CyberPalette.neonCyan)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Token usage · today", "Token 用量 · 今日"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.55))
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(TokenFormat.tokens(today.billable))
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                            if today.cost > 0 {
                                Text(TokenFormat.usd(today.cost))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(CyberPalette.neonPink)
                                    .monospacedDigit()
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    // Per-tool mini bars (today), so the glance shows the mix.
                    if !tools.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(tools.prefix(3), id: \.0) { tool, totals in
                                VStack(spacing: 3) {
                                    Image(systemName: tool.sfSymbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(CyberPalette.neonCyan.opacity(0.9))
                                    Text(TokenFormat.tokens(totals.billable))
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(.primary.opacity(0.6))
                                        .monospacedDigit()
                                }
                            }
                        }
                    } else {
                        Text(L("No usage yet today", "今日暂无用量"))
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.45))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.3))
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .help(L("Open token dashboard", "打开 Token 看板"))
    }
}

/// Shared compact number formatting for the token surfaces.
enum TokenFormat {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if n >= 1_000_000 { return String(format: "%.2fM", d / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", d / 1_000) }
        return "\(n)"
    }
    static func usd(_ v: Double) -> String {
        if v <= 0 { return "—" }
        if v < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", v)
    }
}
