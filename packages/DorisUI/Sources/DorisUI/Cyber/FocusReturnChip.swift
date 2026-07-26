#if os(iOS)
import SwiftUI

/// Small floating capsule shown while a focus session is running but the
/// full-screen dial has been dismissed — the way back in. Without it,
/// closing the dial would leave the clock running with no way to reach it.
///
/// Renders nothing when there's no session, so it costs nothing when idle.
public struct FocusReturnChip: View {
    @ObservedObject private var focus = FocusTimer.shared
    public var onTap: () -> Void

    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        if let s = focus.session {
            Button(action: onTap) {
                HStack(spacing: 7) {
                    FocusRingBadge(diameter: 20, lineWidth: 2.5)
                    Text(s.phase == .finished
                         ? L("Focus done", "专注结束")
                         : CountdownRing.mmss(focus.remaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded)
                            .monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.85))
                    Text(s.displayTitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
    }
}
#endif
