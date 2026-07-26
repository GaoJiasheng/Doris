import SwiftUI

/// The focus indicator as it appears on the notch / edge tab — the single
/// source of truth for what the ring looks like in each state, so the
/// real-notch pip window and the inline edge tab can never drift apart:
///
///   • running  → countdown ring, emptying as the clock runs down
///   • paused   → the same ring, dimmed, with a `II` glyph in the middle
///   • finished → a green checkmark (focus complete)
///
/// Driven by `FocusTimer` at 1 Hz, so it costs nothing per frame.
public struct FocusRingBadge: View {
    @ObservedObject private var focus = FocusTimer.shared
    public var diameter: CGFloat
    public var lineWidth: CGFloat

    public init(diameter: CGFloat = 18, lineWidth: CGFloat = 2.5) {
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Group {
            if let s = focus.session {
                switch s.phase {
                case .finished: finishedCheck
                case .paused:   ring(for: s, dimmed: true).overlay(pauseGlyph)
                default:        ring(for: s, dimmed: false)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func ring(for s: FocusTimer.Session, dimmed: Bool) -> some View {
        let total = Double(s.totalSeconds)
        let prog = total > 0 ? Double(focus.remaining) / total : 0
        let tint = (s.isRest ? CyberPalette.neonCyan : CyberPalette.neonPink)
            .opacity(dimmed ? 0.55 : 1)
        return ZStack {
            CountdownRing(
                progress: prog,
                remaining: focus.remaining,
                tint: tint,
                lineWidth: lineWidth
            )
            // Tiny countdown in the middle. `m:ss` doesn't fit inside an
            // 18pt ring, so show whole minutes remaining and switch to a
            // seconds countdown for the last minute.
            if !dimmed {
                Text(compactRemaining)
                    .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded)
                        .monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    /// Minutes left (rounded up) while over a minute remains; bare seconds
    /// in the final minute — the most information that fits legibly.
    private var compactRemaining: String {
        let r = max(0, focus.remaining)
        return r >= 60 ? "\(Int(ceil(Double(r) / 60)))" : "\(r)"
    }

    /// The `II` hold marker — two short bars, scaled off the ring so it
    /// stays proportional at any badge size.
    private var pauseGlyph: some View {
        HStack(spacing: diameter * 0.11) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: diameter * 0.11, height: diameter * 0.34)
            }
        }
    }

    private var finishedCheck: some View {
        ZStack {
            Circle().fill(CyberPalette.neonGreen.opacity(0.18))
            Circle().stroke(CyberPalette.neonGreen, lineWidth: lineWidth)
            Image(systemName: "checkmark")
                .font(.system(size: diameter * 0.5, weight: .bold))
                .foregroundStyle(CyberPalette.neonGreen)
        }
    }
}

/// The focus ring's right-click actions, shared by every surface that draws
/// the badge so the menu is identical wherever you invoke it.
///
/// Attach with `.contextMenu { FocusRingActions() }`.
public struct FocusRingActions: View {
    @ObservedObject private var focus = FocusTimer.shared

    public init() {}

    public var body: some View {
        if let s = focus.session {
            Menu(L("Set duration", "调整时间")) {
                ForEach([15, 25, 45], id: \.self) { m in
                    Button {
                        FocusTimer.shared.adjust(minutes: m)
                    } label: {
                        // Tick the length the session is already running at.
                        Text(s.durationMin == m ? "✓ \(m) min" : "\(m) min")
                    }
                }
            }
            // Finished sessions have nothing left to hold.
            if s.phase != .finished {
                Button(s.isPaused ? L("Resume", "继续") : L("Pause", "暂停")) {
                    FocusTimer.shared.togglePause()
                }
            }
            Divider()
            Button(L("Stop focus", "停止专注")) { FocusTimer.shared.stop() }
        }
    }
}
