import SwiftUI

/// Ambient backdrop — adaptive cyber gradient (deep purple→black in dark
/// mode, soft cream in light) with breathing pink + cyan radial halos and a
/// faint CRT scanline overlay. Drop this at the back of any screen to get
/// the same cyber atmosphere across Mac windows, iOS screens, and the
/// dropdown panel.
public struct CyberBackground: View {
    /// Strength of the brand color halos. The main window has a smaller
    /// frame and looks washed out at full intensity, so we expose this so
    /// hosts can tune it.
    var haloIntensity: Double
    @Environment(\.colorScheme) private var colorScheme

    /// The halos and scanlines are dark-mode effects: neon glow on a black
    /// page. On a pale page the same halos tint the whole window the accent
    /// color (and muddy it where pink meets cyan), and the scanlines read as
    /// a dirty screen rather than a CRT. Light keeps a faint halo for depth
    /// and drops the scanlines.
    private var isLight: Bool { colorScheme == .light }
    private var halo: Double { haloIntensity * (isLight ? 0.4 : 1.0) }

    public init(haloIntensity: Double = 1.0) {
        self.haloIntensity = haloIntensity
    }

    // STATIC backdrop. Previously the pink halo "breathed" and the scanlines
    // "drifted" via `.repeatForever` animations on @State. SwiftUI animates
    // @State by re-evaluating the body every DISPLAY frame (60–120fps), which
    // forced a full recomposite of the whole window backdrop — including the
    // ~N-Rectangle `.plusLighter` scanline overlay — nonstop. On the main
    // window that alone pinned CPU at 60–90% and tripped the energy warning
    // even when the window was idle. The ambient motion was imperceptible;
    // holding both halo + scanlines static lets CoreAnimation cache the layer
    // once. (Same call AvatarHero already made for its own scanlines.)
    public var body: some View {
        ZStack {
            CyberPalette.backdrop
                .ignoresSafeArea()
            // Pink halo top-left
            RadialGradient(
                colors: [CyberPalette.neonPink.opacity(0.22 * halo), .clear],
                center: UnitPoint(x: 0.18, y: 0.18),
                startRadius: 4, endRadius: 280
            )
            .blur(radius: 20)
            .opacity(0.85)
            .ignoresSafeArea()
            // Cyan rim bottom-right
            RadialGradient(
                colors: [CyberPalette.neonCyan.opacity(0.18 * halo), .clear],
                center: UnitPoint(x: 0.82, y: 0.95),
                startRadius: 0, endRadius: 320
            )
            .blur(radius: 16)
            .ignoresSafeArea()
            if !isLight { scanlines }
        }
    }

    private var scanlines: some View {
        GeometryReader { geo in
            let stripeHeight: CGFloat = 2
            let count = Int(geo.size.height / stripeHeight) + 4
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle()
                        .fill(i.isMultiple(of: 2) ? Color.white.opacity(0.018) : Color.clear)
                        .frame(height: stripeHeight)
                }
            }
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        // Static: with no per-frame offset animation, CoreAnimation composites
        // this overlay once and caches it instead of redrawing every frame.
    }
}

/// Reusable card surface — glass fill + adaptive backdrop + neon stroke.
/// Drop content inside to get the same panel look used across the dropdown
/// panel, Mac main window, and iOS screens.
public struct CyberCard<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = 18, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var body: some View {
        if colorScheme == .light {
            content()
                .background(LightCardSheet(cornerRadius: cornerRadius))
        } else {
            content()
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(CyberPalette.surfaceFill)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .opacity(0.4)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(CyberPalette.panelStroke, lineWidth: 0.8)
                )
        }
    }
}

/// The light-mode card: an opaque white sheet with a soft shadow and a
/// hairline edge.
///
/// Dark cards are glass (`.ultraThinMaterial`) edged in neon, which is right
/// on a black page. On a pale page there is nothing behind the glass to
/// show, so cards took on the backdrop's tint and melted into it, and the
/// neon edge became the only thing marking them out. Lift is what separates
/// a card from a light page — so light cards get a shadow instead.
///
/// `edge` lets a state keep its colored outline (a completed card's done
/// accent); by default the edge is a neutral hairline.
public struct LightCardSheet: View {
    let cornerRadius: CGFloat
    let edge: Color

    public init(cornerRadius: CGFloat, edge: Color = Color.black.opacity(0.07)) {
        self.cornerRadius = cornerRadius
        self.edge = edge
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
            .overlay(shape.strokeBorder(edge, lineWidth: 0.6))
    }
}

/// Compact circular toggle for theme. Tap to flip between Dark and Light
/// modes, animated via `withAnimation`. Used in toolbars and the dropdown
/// panel header so users can switch themes without going through Settings.
public struct ThemeToggleButton: View {
    @ObservedObject private var theme = ThemeSettings.shared

    public init() {}

    public var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                theme.toggle()
            }
        } label: {
            // Icon represents the *destination* theme — the one you'll
            // switch to. In light mode show a moon (click → go dark);
            // in dark mode show a sun (click → go light). Matches the
            // convention every web app uses for theme toggles.
            Image(systemName: theme.mode.toggled.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.75))
                .padding(6)
                .background(
                    Circle()
                        .fill(.primary.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .stroke(CyberPalette.neonCyan.opacity(0.30), lineWidth: 0.6)
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(theme.mode == .dark ? "Switch to light theme" : "Switch to dark theme")
    }
}
