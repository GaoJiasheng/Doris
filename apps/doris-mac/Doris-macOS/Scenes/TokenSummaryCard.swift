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
    @ObservedObject private var weather = WeatherViewModel.shared
    @Query(sort: [SortDescriptor(\TokenUsageDaily.day, order: .reverse)])
    private var dailies: [TokenUsageDaily]
    var onTap: () -> Void

    /// Theme-aware accent gradient (adapts per character pack:
    /// secondary → primary accent).
    private var accent: LinearGradient {
        LinearGradient(colors: [CyberPalette.neonCyan, CyberPalette.neonPink],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        let today = TokenStats.totals(dailies, .today)

        // Borderless glance — no CyberCard box (the Today screen already has
        // plenty of bordered cards below). A gradient headline number + a soft
        // icon + a faint gradient hairline read as a light "today" header.
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(CyberPalette.neonCyan.opacity(0.10)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("TOKEN USAGE · TODAY", "TOKEN 用量 · 今日"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.4))
                        .tracking(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(TokenFormat.tokens(today.billable))
                            .font(.system(size: 25, weight: .heavy, design: .rounded))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                        if today.cost > 0 {
                            Text(TokenFormat.usd(today.cost))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.45))
                                .monospacedDigit()
                        }
                    }
                }

                Spacer(minLength: 8)

                // Weather glance — fills the otherwise-empty right side
                // (same shared snapshot the sidebar avatar uses).
                if let w = weather.snapshot {
                    HStack(spacing: 7) {
                        Image(systemName: w.symbolName)
                            .font(.system(size: 16))
                            .symbolRenderingMode(.multicolor)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Int(w.temperatureC.rounded()))°")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary.opacity(0.85))
                            Text(w.locationName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    .padding(.trailing, 4)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.25))
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { weather.start() }
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
