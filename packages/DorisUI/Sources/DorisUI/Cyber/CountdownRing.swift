import SwiftUI

/// A thin countdown progress ring. `progress` is the fraction of time
/// REMAINING (1 → 0 as it elapses), so the ring empties as the clock runs
/// down. Optional mm:ss label in the center. Shared by the notch idle
/// indicator and the avatar focus overlay.
///
/// Driven at 1 Hz by `FocusTimer.remaining` (the caller recomputes
/// `progress`/`remaining` from it), so it costs nothing per frame.
public struct CountdownRing: View {
    public var progress: Double
    public var remaining: Int
    public var tint: Color
    public var lineWidth: CGFloat
    public var showsLabel: Bool

    public init(
        progress: Double,
        remaining: Int,
        tint: Color = CyberPalette.neonCyan,
        lineWidth: CGFloat = 3,
        showsLabel: Bool = false
    ) {
        self.progress = max(0, min(1, progress))
        self.remaining = max(0, remaining)
        self.tint = tint
        self.lineWidth = lineWidth
        self.showsLabel = showsLabel
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start the sweep at 12 o'clock
            if showsLabel {
                Text(Self.mmss(remaining))
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(2)
            }
        }
    }

    /// Format seconds as `m:ss` (e.g. 25:00, 4:05, 0:09).
    public static func mmss(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
