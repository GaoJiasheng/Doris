import SwiftUI
import DorisCore

/// Shared building blocks for the "Today" surface — used by the iOS
/// `TodayScreen` and the macOS `MainTodayView`. All three components are
/// pure SwiftUI (no UIKit/AppKit reach-through), so the same source
/// renders identically on both platforms. Keeping them here means the
/// visual design only lives in one file — a tweak to e.g. the weather
/// card lands everywhere.

// MARK: - Weather card

/// Full-width ambient weather panel. Top row: large temperature + SF
/// Symbol icon, location and current time. Bottom row: three stat cells
/// (rain / wind / UV) separated by hairline dividers. Card background +
/// border gradient adapt to the active color scheme — dark mode uses a
/// deep purple→navy gradient with stronger neon strokes, light mode
/// switches to a soft lavender→sky-blue with a gentler border.
public struct TodayWeatherCard: View {
    @ObservedObject private var vm: WeatherViewModel
    @ObservedObject private var lang = LanguageSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    public init(vm: WeatherViewModel) {
        self.vm = vm
    }

    private var isDark: Bool { colorScheme == .dark }

    // Theme-aware colors
    private var tempColor: Color      { isDark ? .white : Color(red: 0.08, green: 0.08, blue: 0.18) }
    private var conditionColor: Color { isDark ? .white.opacity(0.68) : Color(red: 0.15, green: 0.15, blue: 0.30).opacity(0.75) }
    private var metaColor: Color      { isDark ? .white.opacity(0.32) : Color(red: 0.2, green: 0.2, blue: 0.35).opacity(0.45) }
    private var statValueColor: Color { isDark ? .white : Color(red: 0.08, green: 0.08, blue: 0.18) }
    private var statLabelColor: Color { isDark ? .white.opacity(0.42) : Color(red: 0.2, green: 0.2, blue: 0.35).opacity(0.5) }
    private var separatorColor: Color { isDark ? .white.opacity(0.07) : Color.black.opacity(0.06) }

    // Card background differs by theme
    private var cardFill: some ShapeStyle {
        if isDark {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.14).opacity(0.92),
                    Color(red: 0.02, green: 0.06, blue: 0.16).opacity(0.88)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        } else {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.95, blue: 1.00).opacity(0.88),
                    Color(red: 0.88, green: 0.92, blue: 0.98).opacity(0.82)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        }
    }

    private var borderGradient: LinearGradient {
        isDark
            ? LinearGradient(
                colors: [CyberPalette.neonPink.opacity(0.55), CyberPalette.neonCyan.opacity(0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [CyberPalette.neonPink.opacity(0.40), CyberPalette.neonCyan.opacity(0.50)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFill)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(isDark ? 0.3 : 0.5))
                )

            Group {
                if let s = vm.snapshot {
                    weatherContent(s)
                } else if vm.isLoading {
                    loadingView
                } else {
                    emptyView
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderGradient, lineWidth: isDark ? 0.9 : 0.7)
        )
        // Subtle shadow on light mode for depth
        .shadow(
            color: isDark ? .clear : Color(red: 0.55, green: 0.60, blue: 0.85).opacity(0.18),
            radius: 12, x: 0, y: 4
        )
    }

    private func weatherContent(_ s: WeatherSnapshot) -> some View {
        VStack(spacing: 0) {
            // Top: big temp + icon + location
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: s.symbolName)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(iconPrimary(s), isDark ? Color.white.opacity(0.85) : Color(red: 0.3, green: 0.35, blue: 0.5).opacity(0.9))
                            .font(.system(size: 42, weight: .light))
                        Text("\(Int(s.temperatureC.rounded()))°")
                            .font(.system(size: 64, weight: .thin, design: .rounded).monospacedDigit())
                            .foregroundStyle(tempColor)
                    }
                    Text(WeatherCode.text(for: s.weatherCode))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(conditionColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(CyberPalette.neonCyan.opacity(isDark ? 0.9 : 1.0))
                        Text(s.locationName)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(CyberPalette.neonCyan.opacity(isDark ? 0.9 : 1.0))
                            .lineLimit(1)
                    }
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 13, design: .monospaced).monospacedDigit())
                        .foregroundStyle(metaColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Gradient divider
            LinearGradient(
                colors: [CyberPalette.neonPink.opacity(isDark ? 0.45 : 0.35),
                         CyberPalette.neonCyan.opacity(isDark ? 0.45 : 0.35)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 0.6)
            .padding(.horizontal, 20)

            // Stat row
            HStack(spacing: 0) {
                statCell(
                    icon: "drop.fill",
                    value: "\(Int(s.precipitationProbability.rounded()))%",
                    label: L("Rain", "降水"),
                    tint: RainScale.tint(s.precipitationProbability)
                )
                Rectangle().fill(separatorColor).frame(width: 0.6).padding(.vertical, 6)
                statCell(
                    icon: "wind",
                    value: "\(Int(s.windSpeedKmh.rounded())) km/h",
                    label: WindScale.compass(s.windDirectionDeg),
                    tint: CyberPalette.neonCyan
                )
                Rectangle().fill(separatorColor).frame(width: 0.6).padding(.vertical, 6)
                statCell(
                    icon: "sun.max.trianglebadge.exclamationmark.fill",
                    value: UVScale.label(s.uvIndex),
                    label: L("UV", "紫外线"),
                    tint: UVScale.tint(s.uvIndex)
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func statCell(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(statValueColor)
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(statLabelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().tint(CyberPalette.neonCyan.opacity(0.6))
            Text(L("Loading weather…", "加载天气中…"))
                .font(.caption.monospaced())
                .foregroundStyle(conditionColor)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        Text(L("Weather unavailable", "天气不可用"))
            .font(.caption.monospaced())
            .foregroundStyle(metaColor)
            .padding(32)
            .frame(maxWidth: .infinity)
    }

    private func iconPrimary(_ s: WeatherSnapshot) -> Color {
        switch s.symbolName {
        case "sun.max.fill", "moon.stars.fill", "moon.fill":
            return Color(red: 1.0, green: 0.80, blue: 0.25)
        case "snowflake", "cloud.snow.fill", "cloud.sleet.fill":
            return isDark ? .white : Color(red: 0.6, green: 0.75, blue: 0.95)
        case "cloud.bolt.rain.fill", "cloud.bolt.fill":
            return Color(red: 1.0, green: 0.82, blue: 0.25)
        default:
            return Color(red: 0.0, green: 0.82, blue: 1.0)
        }
    }
}

// MARK: - Pinned note card

/// Compact card used in the pinned grid. Fixed 92pt height so the grid
/// keeps a clean baseline regardless of which optional bits (checklist
/// progress bar / due-date chip) the note carries. The dueChipColor
/// drives both the chip itself and the progress bar's accent — overdue
/// → red, today → yellow, future → cyan.
public struct TodayPinnedCard: View {
    private let note: Note

    public init(note: Note) {
        self.note = note
    }

    /// True when the user considers this card "done" — either the note's
    /// own `done` flag is set, or it's a checklist whose items are all
    /// checked. Drives the entire completed-state visual treatment
    /// (strikethrough title, green border, DONE pill, seal icon, dim).
    private var isCompleted: Bool {
        if note.done { return true }
        if note.isChecklist {
            let items = note.checklistItems ?? []
            return !items.isEmpty && items.allSatisfy(\.done)
        }
        return false
    }

    private var dueChipColor: Color {
        guard let d = note.dueDate else { return CyberPalette.neonCyan }
        if d < Date() { return .red }
        if Calendar.current.isDateInToday(d) { return .yellow }
        return CyberPalette.neonCyan
    }

    private var dueLabel: String? {
        guard let d = note.dueDate else { return nil }
        let cal = Calendar.current
        if d < Date() {
            let days = cal.dateComponents([.day], from: d, to: Date()).day ?? 0
            if days == 0 { return L("Today", "今天") }
            return L("\(days)d overdue", "逾期 \(days) 天")
        }
        if cal.isDateInToday(d)    { return L("Today", "今天") }
        if cal.isDateInTomorrow(d) { return L("Tomorrow", "明天") }
        let days = cal.dateComponents([.day], from: Date(), to: d).day ?? 0
        if days < 7 { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top: icon · title · pin/seal
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: note.isChecklist ? "checklist" : "note.text")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCompleted ? CyberPalette.doneAccent : CyberPalette.neonCyan)
                    .frame(width: 16)
                Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    // Strikethrough + dim when done — the strongest single
                    // signal that this card is "settled". Color of the
                    // strikethrough itself is neon-green so it reads as
                    // "completed" rather than "deleted/cancelled".
                    .strikethrough(isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                    .foregroundStyle(isCompleted
                        ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.45))
                        : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Pinned cards normally show a tiny pin glyph; when done we
                // swap to a green seal so the badge itself signals state.
                Image(systemName: isCompleted ? "checkmark.seal.fill" : "pin.fill")
                    .font(.system(size: isCompleted ? 11 : 9))
                    .foregroundStyle(
                        isCompleted
                            ? CyberPalette.doneAccent
                            : CyberPalette.neonCyan.opacity(0.45)
                    )
            }

            Spacer(minLength: 0)

            // Bottom: DONE pill if completed, otherwise progress / due meta
            if isCompleted {
                donePill
            } else {
                bottomMeta
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // Tightened from 92pt → 76pt — the original height was sized for
        // iOS's narrow 2-column grid where 2-line titles were common.
        // Mac/popup grids run wider (180pt min) so most titles fit on
        // one line, leaving the card feeling top-heavy. 76pt still
        // accommodates a 2-line title via the Spacer absorbing slack.
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.45))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            (isCompleted ? CyberPalette.doneAccent : CyberPalette.neonCyan)
                                .opacity(0.04)
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    (isCompleted ? CyberPalette.doneAccent : CyberPalette.neonCyan)
                        .opacity(isCompleted ? 0.45 : 0.22),
                    lineWidth: 0.7
                )
        )
        // Whole card recedes a touch when done so unfinished cards "pop"
        // forward in the grid. Animated so toggling a checkbox elsewhere
        // gives a satisfying fade rather than a hard cut.
        .opacity(isCompleted ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isCompleted)
    }

    /// "DONE / 已完成" pill — replaces the due-date chip for completed
    /// cards. Uppercase monospaced caps, mini check glyph, neon-green
    /// tinted fill + stroke. Sized to mirror the dueRow chip so the
    /// card baseline doesn't shift between states.
    private var donePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text(L("DONE", "已完成"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundStyle(CyberPalette.doneAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(CyberPalette.doneAccent.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(CyberPalette.doneAccent.opacity(0.55), lineWidth: 0.7)
        )
    }

    private var checklistProgress: (done: Int, total: Int)? {
        guard note.isChecklist, let items = note.checklistItems, !items.isEmpty else {
            return nil
        }
        return (items.filter(\.done).count, items.count)
    }

    @ViewBuilder
    private var bottomMeta: some View {
        let progress = checklistProgress
        let due = dueLabel

        // Three permitted pieces of info: title (above) · progress · due.
        // Both present → progress row over due chip row.
        if progress != nil || due != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let p = progress {
                    progressRow(done: p.done, total: p.total)
                }
                if let label = due {
                    dueRow(label: label)
                }
            }
        }
    }

    private func progressRow(done: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [CyberPalette.neonPink, CyberPalette.neonCyan],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: g.size.width * (Double(done) / Double(total)), height: 3)
                }
            }
            .frame(height: 3)
            Text("\(done)/\(total)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.55))
        }
    }

    private func dueRow(label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(dueChipColor)
    }
}

// MARK: - Calendar / upcoming row

/// Wide row used in the "Upcoming" list — left date column (big day
/// number + abbreviated month), left accent bar fading top→bottom, title
/// + due label on the right, and a chevron indicating tappability. Same
/// chipColor logic as the pinned card (overdue/today/future).
public struct TodayCalendarRow: View {
    private let note: Note

    public init(note: Note) {
        self.note = note
    }

    private var due: Date { note.dueDate ?? .distantFuture }

    /// Same logic as TodayPinnedCard — the row is "done" if the note's
    /// own flag is set or all checklist items are checked. Keeping the
    /// two computeds identical (rather than factoring to Note) is OK
    /// for now; if a third surface adopts this we'll move it.
    private var isCompleted: Bool {
        if note.done { return true }
        if note.isChecklist {
            let items = note.checklistItems ?? []
            return !items.isEmpty && items.allSatisfy(\.done)
        }
        return false
    }

    private var chipColor: Color {
        // When done, the whole row goes neon-green — date column, accent
        // bar, due-chip text. Single accent flip = one clear "settled"
        // signal even on the small calendar row.
        if isCompleted { return CyberPalette.doneAccent }
        if due < Date() { return .red }
        if Calendar.current.isDateInToday(due) { return .yellow }
        return CyberPalette.neonCyan
    }

    private var dueLabel: String {
        let cal = Calendar.current
        if due < Date() {
            let days = cal.dateComponents([.day], from: due, to: Date()).day ?? 0
            if days == 0 { return L("Today", "今天") }
            return L("\(days)d overdue", "逾期 \(days) 天")
        }
        if cal.isDateInToday(due)     { return L("Today", "今天") }
        if cal.isDateInTomorrow(due)  { return L("Tomorrow", "明天") }
        let days = cal.dateComponents([.day], from: Date(), to: due).day ?? 0
        if days < 7 { return due.formatted(.dateTime.weekday(.wide)) }
        return due.formatted(.dateTime.month(.abbreviated).day())
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Date column — sized to feel like a peer of `TodayPinnedCard`
            // (14pt titles, 11pt chips, 14pt corner radius). The original
            // 30pt day number + 17pt title was iOS-phone-scaled and read
            // as chunky on mac next to the pinned grid.
            VStack(spacing: 1) {
                Text(due.formatted(.dateTime.day()))
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(chipColor)
                Text(due.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(chipColor.opacity(0.7))
            }
            .frame(width: 38)

            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [chipColor.opacity(0.8), chipColor.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 2)
                .padding(.vertical, 3)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .strikethrough(isCompleted, color: CyberPalette.doneAccent.opacity(0.85))
                    .foregroundStyle(isCompleted
                        ? AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(0.45))
                        : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if isCompleted {
                        // Replaces the due chip — uppercase mono "DONE /
                        // 已完成" pill. Slightly smaller than the pinned
                        // card's version to fit the row's tighter rhythm.
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                            Text(L("DONE", "已完成"))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(0.7)
                        }
                        .foregroundStyle(CyberPalette.doneAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CyberPalette.doneAccent.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(CyberPalette.doneAccent.opacity(0.55), lineWidth: 0.7)
                        )
                    } else {
                        Text(dueLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(chipColor)
                    }
                    if note.isChecklist {
                        let items = note.checklistItems ?? []
                        let done = items.filter(\.done).count
                        if !items.isEmpty {
                            Text("· \(done)/\(items.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.4))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.15))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    chipColor.opacity(isCompleted ? 0.35 : 0.12),
                    lineWidth: isCompleted ? 0.8 : 0.6
                )
        )
        // Match the pinned card: completed rows dim slightly so unfinished
        // ones lead the list visually.
        .opacity(isCompleted ? 0.72 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: isCompleted)
    }
}
