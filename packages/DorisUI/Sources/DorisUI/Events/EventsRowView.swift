import SwiftUI
import DorisCore
import DorisIPC

public struct EventsRowView: View {
    public let message: Message

    public init(message: Message) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Leading severity stripe — pink for `.critical`, cyan for
            // `.reminder`, and the same cyan at low alpha for `.info`
            // so a list of routine events doesn't feel noisy. Hue is
            // restricted to the popup's two-color brand palette
            // (pink + cyan); hierarchy is encoded by intensity, not
            // by introducing a third hue.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(EventLevelStyle.color(for: message.level))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .opacity(EventLevelStyle.intensity(for: message.level))

            Image(systemName: message.iconName ?? message.source.sfSymbol)
                .foregroundStyle(EventLevelStyle.color(for: message.level))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.title)
                        .font(.headline)
                    if message.level != .info {
                        levelBadge(for: message.level)
                    }
                    Spacer()
                    // Absolute timestamp (MM/dd HH:mm). Relative
                    // ("5 min ago") was hard to scan when triaging
                    // a long event list — the eye keeps adding up
                    // offsets in its head. Absolute reads in O(1).
                    Text(message.receivedAt,
                         format: .dateTime.month(.twoDigits).day(.twoDigits)
                                          .hour(.twoDigits(amPM: .omitted))
                                          .minute(.twoDigits))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let body = message.bodyMarkdown, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    Text(message.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let appID = message.sourceAppId {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(appID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if message.displayMode == .fix {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func levelBadge(for level: EventLevel) -> some View {
        let color = EventLevelStyle.color(for: level)
        HStack(spacing: 3) {
            Image(systemName: level.sfSymbol)
                .font(.system(size: 9, weight: .semibold))
            Text(level.displayName.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .kerning(0.5)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.5))
    }
}

/// Shared color palette for `EventLevel`. Lives next to the row view so
/// other surfaces (banner, anchor dropdown, widget) can reach for the
/// same colors and stay visually consistent.
///
/// Three distinct hues, each tuned to land cleanly on both the deep-
/// purple dark backdrop and the cream light backdrop — i.e. the same
/// RGB values are used regardless of theme. Critical keeps the brand
/// pink (the popup's alarm color); reminder and info pick warm and
/// cool accents *outside* the popup's strict pink+cyan vocabulary so
/// the three levels are immediately distinguishable by hue.
///
///   - critical → `neonPink`  (alarm — same brand pink as popup chrome)
///   - reminder → `levelOrange` (warm "look at this" tone)
///   - info     → `levelSkyBlue` (cool "by the way" tone)
public enum EventLevelStyle {
    /// Warm orange used for `.reminder`. Bright enough to stand against
    /// dark backdrops, saturated enough to read clearly against light.
    public static let levelOrange = Color(red: 1.0, green: 0.62, blue: 0.18)

    /// Soft sky blue used for `.info`. Distinctly different from the
    /// popup's `neonCyan` so it doesn't read as a dimmed brand accent;
    /// instead it lands as its own "low-priority info" hue.
    public static let levelSkyBlue = Color(red: 0.40, green: 0.72, blue: 1.0)

    public static func color(for level: EventLevel) -> Color {
        switch level {
        case .critical: return CyberPalette.neonPink
        case .reminder: return levelOrange
        case .info:     return levelSkyBlue
        }
    }

    public static func intensity(for level: EventLevel) -> Double {
        switch level {
        case .critical: return 1.0
        case .reminder: return 1.0
        case .info:     return 0.85
        }
    }
}
