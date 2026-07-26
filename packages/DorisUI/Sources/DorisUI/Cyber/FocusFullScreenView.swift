#if os(iOS)
import SwiftUI

/// The iOS focus surface: one big ring, the clock inside it, and a small ✕.
/// Deliberately spare — while you're focusing this is the only thing on
/// screen, so there is nothing here but the task, the time, and the way out.
///
/// Presented as a `fullScreenCover` by `RootTabView`. Dismissing does NOT
/// stop the clock (it keeps running, and the ring chip brings you back);
/// "结束" is the explicit stop.
public struct FocusFullScreenView: View {
    @ObservedObject private var focus = FocusTimer.shared
    @Environment(\.colorScheme) private var colorScheme
    /// Close the cover (the session keeps running).
    public var onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var accent: Color {
        guard let s = focus.session else { return CyberPalette.neonCyan }
        if s.phase == .finished { return CyberPalette.neonGreen }
        return s.isRest ? CyberPalette.neonCyan : CyberPalette.neonPink
    }

    public var body: some View {
        ZStack {
            CyberBackground(haloIntensity: 0.9)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                closeRow
                Spacer(minLength: 0)
                if let s = focus.session {
                    dial(for: s)
                    Spacer(minLength: 0)
                    controls(for: s)
                } else {
                    // Session cleared out from under us (e.g. stopped on the
                    // Mac and synced) — nothing to show, so leave.
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        // Focus deserves the whole screen — no status-bar clutter.
        .statusBarHidden(true)
        .onChange(of: focus.session == nil) { _, cleared in
            if cleared { onClose() }
        }
    }

    // MARK: - Chrome

    private var closeRow: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.5))
                    // Generous hit area around a deliberately small glyph.
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(.ultraThinMaterial)
                    )
            }
            .accessibilityLabel(L("Close", "关闭"))
        }
        .padding(.top, 8)
    }

    // MARK: - The dial

    private func dial(for s: FocusTimer.Session) -> some View {
        let total = Double(s.totalSeconds)
        let progress = total > 0 ? max(0, min(1, Double(focus.remaining) / total)) : 0
        return VStack(spacing: 26) {
            ZStack {
                // Track
                Circle()
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07),
                            lineWidth: 16)

                // Remaining arc. Gradient reads as a single sweep of light
                // rather than a flat band.
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [accent.opacity(0.55), accent],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))     // start at 12 o'clock
                    .shadow(color: accent.opacity(0.45), radius: 12)
                    // Brief ease on each 1 Hz step — enough to feel alive
                    // without a per-frame animation running for 25 minutes.
                    .animation(.easeOut(duration: 0.3), value: progress)
                    .opacity(s.isPaused ? 0.45 : 1)

                center(for: s)
            }
            .frame(maxWidth: 300)
            .aspectRatio(1, contentMode: .fit)

            Text(s.displayTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func center(for s: FocusTimer.Session) -> some View {
        if s.phase == .finished {
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(CyberPalette.neonGreen)
                Text(s.isRest ? L("Break over", "休息结束") : L("Focus done", "专注结束"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        } else {
            VStack(spacing: 6) {
                Text(CountdownRing.mmss(focus.remaining))
                    .font(.system(size: 62, weight: .semibold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(s.isPaused
                     ? L("Paused", "已暂停")
                     : L("\(s.durationMin) min", "\(s.durationMin) 分钟"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.45))
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Controls

    /// Extension presets offered when a session ends: a quick top-up, a short
    /// round, and a full pomodoro.
    private static let extendPresets = [5, 15, 25]

    @ViewBuilder
    private func controls(for s: FocusTimer.Session) -> some View {
        if s.phase == .finished {
            VStack(spacing: 18) {
                // Keep going for another N minutes on the same task…
                VStack(spacing: 9) {
                    Text(L("Keep going", "再续"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.45))
                    HStack(spacing: 10) {
                        ForEach(Self.extendPresets, id: \.self) { m in
                            compactPill(L("\(m) min", "\(m) 分钟")) {
                                focus.adjust(minutes: m)
                            }
                        }
                    }
                }
                // …or walk away / tick it off.
                HStack(spacing: 12) {
                    pill(L("Exit", "退出"), filled: false) { focus.stop() }
                    if focus.canComplete {
                        pill(L("Complete", "完成任务"), filled: true) { focus.completeTask() }
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                pill(s.isPaused ? L("Resume", "继续") : L("Pause", "暂停"),
                     filled: false) { focus.togglePause() }
                pill(L("End", "结束"), filled: true) { focus.stop() }
            }
        }
    }

    /// Narrower pill — three of these sit in one row on a phone.
    private func compactPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? Color.white : .primary.opacity(0.8))
                .frame(minWidth: 108)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(filled
                                   ? AnyShapeStyle(accent.opacity(0.85))
                                   : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(
                    Capsule().strokeBorder(
                        filled ? Color.clear : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}
#endif
