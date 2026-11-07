import SwiftUI
import DorisCore

/// The three numbers Doris tracks per day, shared by the Stats tab, the
/// notch read-out and the iPhone's view.
public enum ActivityMetric: String, CaseIterable, Identifiable, Sendable {
    case tokens, meeting, words

    public var id: String { rawValue }

    @MainActor public var title: String {
        switch self {
        case .tokens:  return "Token"
        case .meeting: return L("Meetings", "会议")
        case .words:   return L("Typing", "打字")
        }
    }

    public var symbol: String {
        switch self {
        case .tokens:  return "bolt.fill"
        case .meeting: return "video.fill"
        case .words:   return "character.cursor.ibeam"
        }
    }

    /// Fixed per metric (not themed) so a number reads the same everywhere.
    public var color: Color {
        switch self {
        case .tokens:  return Color(light: Color(red: 0.72, green: 0.42, blue: 0.02),
                                    dark: Color(red: 1.0, green: 0.74, blue: 0.25))
        case .meeting: return Color(light: Color(red: 0.05, green: 0.50, blue: 0.40),
                                    dark: Color(red: 0.35, green: 0.85, blue: 0.68))
        case .words:   return Color(light: Color(red: 0.12, green: 0.40, blue: 0.75),
                                    dark: Color(red: 0.48, green: 0.72, blue: 1.0))
        }
    }

    /// The Stats page's colour card: deeper and more saturated than `color`,
    /// so white type holds up on it in either appearance.
    public var heroGradient: LinearGradient {
        let c: [Color]
        switch self {
        case .tokens:  c = [Color(red: 0.95, green: 0.52, blue: 0.08), Color(red: 0.84, green: 0.20, blue: 0.27)]
        case .meeting: c = [Color(red: 0.03, green: 0.60, blue: 0.53), Color(red: 0.05, green: 0.36, blue: 0.68)]
        case .words:   c = [Color(red: 0.25, green: 0.38, blue: 0.96), Color(red: 0.55, green: 0.22, blue: 0.86)]
        }
        return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var heroShadow: Color {
        switch self {
        case .tokens:  return Color(red: 0.84, green: 0.30, blue: 0.15)
        case .meeting: return Color(red: 0.04, green: 0.46, blue: 0.62)
        case .words:   return Color(red: 0.38, green: 0.28, blue: 0.90)
        }
    }

    /// Dark text for white chips on the colour card.
    public var heroInk: Color {
        switch self {
        case .tokens:  return Color(red: 0.62, green: 0.22, blue: 0.08)
        case .meeting: return Color(red: 0.02, green: 0.32, blue: 0.40)
        case .words:   return Color(red: 0.26, green: 0.20, blue: 0.68)
        }
    }

    /// Colours for the parts of a whole, largest first; the last one is the
    /// quiet "everything else".
    public var ramp: [Color] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        let grey = Color.gray.opacity(0.55)
        switch self {
        case .tokens:
            return [rgb(0.95, 0.52, 0.08), rgb(0.89, 0.27, 0.27), rgb(0.72, 0.25, 0.60), rgb(0.42, 0.33, 0.82), grey]
        case .meeting:
            return [rgb(0.03, 0.60, 0.53), rgb(0.05, 0.50, 0.75), rgb(0.20, 0.36, 0.85), rgb(0.42, 0.33, 0.82), grey]
        case .words:
            return [rgb(0.25, 0.38, 0.96), rgb(0.55, 0.22, 0.86), rgb(0.80, 0.25, 0.65), rgb(0.03, 0.60, 0.53), grey]
        }
    }

    public func value(_ t: ActivityTotal) -> Int {
        switch self {
        case .tokens:  return t.tokens
        case .meeting: return t.meetingSeconds
        case .words:   return t.typedWords
        }
    }

    /// Short form for the notch and chart axes: "2.3M", "1:20", "3.2k".
    public func compact(_ v: Int) -> String {
        switch self {
        case .tokens:  return ActivityFormat.count(v)
        case .meeting: return ActivityFormat.clock(v)
        case .words:   return ActivityFormat.count(v)
        }
    }

    /// For tiles that may hold long totals: like `compact`, but meeting time
    /// past 100 hours drops the minutes ("128 h").
    public func compactLong(_ v: Int) -> String {
        if self == .meeting, v >= 100 * 3600 { return "\(v / 3600) h" }
        return compact(v)
    }

    /// Long form for cards: "2.3M", "1 小时 20 分", "3,240".
    @MainActor public func full(_ v: Int) -> String {
        switch self {
        case .tokens:  return ActivityFormat.count(v)
        case .meeting: return ActivityFormat.duration(v)
        case .words:   return v.formatted()
        }
    }
}

public enum ActivityFormat {
    /// 950 → "950", 3240 → "3.2k", 23 400 → "23.4k", 2 300 000 → "2.3M".
    public static func count(_ n: Int) -> String {
        let d = Double(n)
        switch n {
        case ..<1_000:          return "\(n)"
        case ..<100_000:        return trim(String(format: "%.1f", d / 1_000)) + "k"
        case ..<1_000_000:      return String(format: "%.0f", d / 1_000) + "k"
        case ..<100_000_000:    return trim(String(format: "%.1f", d / 1_000_000)) + "M"
        case ..<1_000_000_000:  return String(format: "%.0f", d / 1_000_000) + "M"
        default:                return trim(String(format: "%.1f", d / 1_000_000_000)) + "B"
        }
    }

    /// Seconds as h:mm ("1:20"), or "25m" under an hour.
    public static func clock(_ seconds: Int) -> String {
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    @MainActor public static func duration(_ seconds: Int) -> String {
        let m = seconds / 60
        let h = m / 60, r = m % 60
        if h == 0 { return L("\(r) min", "\(r) 分钟") }
        if r == 0 { return L("\(h) h", "\(h) 小时") }
        return L("\(h) h \(r) min", "\(h) 小时 \(r) 分")
    }

    /// Short form for rows: "$29.35", "$4,055", "$131k".
    public static func usd(_ v: Double) -> String {
        if v <= 0 { return "—" }
        if v < 0.01 { return "<$0.01" }
        if v < 1_000 { return String(format: "$%.2f", v) }
        if v < 100_000 { return usdFull(v) }
        return String(format: "$%.0fk", v / 1_000)
    }

    /// Whole dollars above $1,000, for headlines: "$29.35", "$130,942".
    public static func usdFull(_ v: Double) -> String {
        if v < 1_000 { return usd(v) }
        return "$" + Int(v.rounded()).formatted(.number.locale(Locale(identifier: "en_US")))
    }

    private static func trim(_ s: String) -> String {
        s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
