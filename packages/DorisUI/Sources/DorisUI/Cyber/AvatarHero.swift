import SwiftUI
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the avatar is currently doing. Each case maps to a bundled video
/// clip (frames live at `Bundle.module/HeroAnim/<clip>/`):
///
/// - **Loop clips**: idle, listening, walking, sleeping — cycle forever.
/// - **One-shot clips**: greeting, alerted, celebrating, confused — play
///   once, then automatically revert to the underlying loop mood.
public enum HeroMood: Equatable {
    case idle
    case greeting
    case alerted
    case listening
    case celebrating
    case sleeping
    case walking
    case confused

    /// Bundled clip directory name, e.g. `"idle"` → frames at
    /// `HeroAnim/idle/idle_0001.png ... idle_0065.png`. We currently
    /// don't have a `sleeping` clip — fall back to `walking` for now (or
    /// idle) so the player has something to render.
    var clipName: String {
        switch self {
        case .idle:        return "idle"
        case .greeting:    return "greeting"
        case .alerted:     return "alerted"
        case .listening:   return "listening"
        case .celebrating: return "celebrating"
        case .walking:     return "walking"
        case .confused:    return "confused"
        case .sleeping:    return "idle"     // no dedicated clip yet
        }
    }

    var isLooping: Bool {
        switch self {
        case .idle, .listening, .walking, .sleeping: return true
        case .greeting, .alerted, .celebrating, .confused: return false
        }
    }
}

/// Cross-platform cyber-girl hero card. The character is now an animated
/// PNG-frame clip (16 fps, 65 frames each) — replaces the static image
/// that used to be transformed via SwiftUI scaleEffect/rotation. Mood
/// changes swap clips. Environment effects (cyan halo intensity, opacity
/// for sleep, particle bursts, day/night halo, scanlines) still layer on
/// top — they read as ambient feedback rather than character motion.
public struct AvatarHero: View {
    var mood: HeroMood
    var compact: Bool
    var showWeather: Bool
    /// True (default) clips + strokes the standard rounded chrome. Set
    /// false when the parent applies its own clip (e.g. expanded panel
    /// uses an uneven-rounded clip on the left column).
    var selfChrome: Bool
    /// When true, render ONLY the animated character (transparent PNG) —
    /// no backdrop, scanlines, HUD brackets, stars, weather or chrome. Used
    /// by the floating desktop pet so just the character sits on the desktop.
    var transparentBackdrop: Bool
    /// When false, the view ignores taps / hover (the host handles all
    /// interaction — e.g. the desktop pet window does click vs drag itself).
    var interactive: Bool

    public init(
        mood: HeroMood = .idle,
        compact: Bool = false,
        showWeather: Bool = false,
        selfChrome: Bool = true,
        transparentBackdrop: Bool = false,
        interactive: Bool = true
    ) {
        self.mood = mood
        self.compact = compact
        self.showWeather = showWeather
        self.selfChrome = selfChrome
        self.transparentBackdrop = transparentBackdrop
        self.interactive = interactive
    }

    /// Shared app-wide weather state — one network round-trip every
    /// 10 minutes regardless of how many AvatarHero instances mount or
    /// how many times the dropdown opens. Was previously a per-view
    /// `@StateObject`, which meant each dropdown reopen kicked off a
    /// fresh fetch.
    @ObservedObject private var weather = WeatherViewModel.shared
    @ObservedObject private var heroEvents = HeroEvents.shared
    /// Active visual identity. Switching the selected pack swaps the
    /// character's frames live (the player keys its cache on the pack's
    /// anim directory, so the same mood name reloads new art).
    @ObservedObject private var packStore = CharacterPackStore.shared
    /// Drives the day/night look of the backdrop: light scheme → bright
    /// daytime sky with faint dust motes; dark scheme → deep-space night
    /// with a full starfield. Both windows that host the hero apply
    /// `.preferredColorScheme(theme.mode.colorScheme)`, so this tracks the
    /// user's 白天/夜间 (light/dark) setting.
    @Environment(\.colorScheme) private var colorScheme
    private var isDay: Bool { colorScheme == .light }
    /// Procedural starfield. Generated once on view init so positions stay
    /// stable across renders — only the per-star brightness twinkles.
    /// 100 stars still reads as a dense field in a 200pt-wide card and
    /// trims ~30 % of the Canvas drawing work per frame.
    @State private var stars: [HeroStar] = (0..<100).map { _ in HeroStar.random() }
    /// Cursor position in the card's local coordinate space, or nil when
    /// the cursor isn't over the card. Drives the cursor halo + nearby-
    /// star boost. Mac-only; iOS doesn't have hover.
    @State private var cursorPos: CGPoint? = nil
    /// Timestamp of the last cursor update — `onContinuousHover` is
    /// throttled to ~30 Hz against this so high-polling-rate input
    /// devices don't hammer the view tree.
    @State private var lastCursorUpdate: Date = .distantPast
    /// Active click ripples — each is a circle that expands and fades
    /// over ~1.2s starting from its `origin`.
    @State private var ripples: [Ripple] = []
    /// Recent click timestamps used to detect a "rapid poke" — three
    /// clicks within 0.6s fires the `confused` reaction instead of a
    /// greeting (the "stop poking me" easter egg).
    @State private var recentClicks: [Date] = []

    // MARK: - State

    /// What's actually playing right now. Distinct from `mood` (the param
    /// telling us the underlying loop) because one-shot reactions drive
    /// `playingMood` temporarily, then revert.
    @State private var playingMood: HeroMood = .idle
    /// One-shot hold — set to .greeting/.alerted/.celebrating/.confused
    /// when an event fires; cleared when the clip finishes playing.
    @State private var pendingOneShot: HeroMood?

    // Environment effect state
    @State private var moodOpacity: Double = 1.0
    @State private var scanlineOffset: CGFloat = 0
    @State private var particles: [HeroParticle] = []
    @State private var autoSleeping: Bool = false

    // MARK: - Body

    public var body: some View {
        // Only the canvas-based ambient layers (twinkling stars, particles,
        // ripples) live inside `TimelineView` — they're the parts that
        // need per-frame redraws. Everything else (the character clip,
        // scanlines, corner brackets, weather pill) is OUTSIDE the
        // timeline so SwiftUI doesn't re-layout the whole tree at frame
        // rate. The character has its own internal 16fps `TimelineView`,
        // so it animates independently without dragging this body with it.
        //
        // Rate dropped from 30fps → 12fps. Twinkle is a slow sin, ripples
        // and particles are forgiving — 12fps looks identical to the eye
        // and cuts CPU enormously (was sitting at 60–80 % during launch
        // with the old 30fps full-tree re-eval).
        ZStack {
            // Desktop-pet mode (transparentBackdrop) renders ONLY the
            // character — the clip's PNGs are alpha-transparent, so just the
            // character floats on the desktop with no card / backdrop / HUD.
            if !transparentBackdrop {
                ambientBackdrop        // day-sky / night-space gradient
                cursorHalo             // re-renders only on cursor move (Mac)
                animatedAmbientLayers  // 12fps Canvas layer for stars/particles/ripples
                scanlines              // CoreAnimation-driven offset, cheap
            }
            character                  // owns its own 16fps player TimelineView
            if !transparentBackdrop {
                cornerAccents          // static
                if showWeather { weatherOverlay }
            }
        }
        .opacity(moodOpacity)
        .modifier(SelfChromeModifier(enabled: selfChrome && !transparentBackdrop, compact: compact))
        .allowsHitTesting(interactive)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
            handleClick(at: point)
        }
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                // `onContinuousHover` fires on every mouse-moved event
                // (200+ Hz from a high-polling-rate trackpad/mouse). Each
                // change of `cursorPos` re-renders both `cursorHalo` and
                // the starfield Canvas (cursor proximity boost). Throttle
                // to ~30 Hz — same visual feel, far less view work.
                let now = Date()
                if now.timeIntervalSince(lastCursorUpdate) > 0.033 {
                    cursorPos = p
                    lastCursorUpdate = now
                }
            case .ended:
                cursorPos = nil
            }
        }
        #endif
        .onAppear {
            playingMood = mood
            startPerpetualLoops()
            scheduleAutoSleep()
            // `start()` is idempotent — kicks off the singleton's 10-min
            // refresh loop on first call, no-op afterwards. We never
            // `stop()` it on disappear: another AvatarHero instance
            // (main window vs dropdown) might still be observing, and
            // the loop is cheap regardless.
            if showWeather { weather.start() }
        }
        .onChange(of: mood) { _, new in handleMoodChange(new) }
        // Bus-driven one-shots respect any one-shot already in flight —
        // a greeting on window-open shouldn't get cut short by a sync
        // celebration or an arriving alert. Direct user clicks still
        // call `fireOneShot` directly (see `handleClick`) and bypass
        // this gate, since a click is a deliberate poke and the user
        // expects feedback.
        .onChange(of: heroEvents.lastCelebration) { _, _ in busFireOneShot(.celebrating) }
        .onChange(of: heroEvents.lastGreeting)    { _, _ in busFireOneShot(.greeting) }
        .onChange(of: heroEvents.lastAlert)       { _, _ in busFireOneShot(.alerted) }
        .onChange(of: heroEvents.isListening)     { _, on in setListening(on) }
    }

    /// The three Canvas-backed ambient layers stacked into one
    /// `TimelineView` so they share a single per-frame tick. Putting them
    /// here (instead of around the whole `body`) keeps the layout engine
    /// from churning the static parts of the hero card — character
    /// clip, weather pill, brackets, etc. — at frame rate.
    ///
    /// **Only the per-frame canvases live inside the timeline.** The
    /// background gradient and cursor halo are layered outside in
    /// `body` because they don't depend on `now`. If they were inside
    /// the closure SwiftUI would re-evaluate them 12 times a second
    /// even though their content hasn't changed.
    private var animatedAmbientLayers: some View {
        // 20 fps for ambient (twinkle / particles / ripples). Twinkle is
        // a slow sin and looks identical at 20fps vs 30fps; particles
        // and ripples fade over ~1s so a couple fewer interpolated
        // frames is invisible. AvatarHero is only mounted while the
        // dropdown is open — closing the panel tears the SwiftUI tree
        // down (see `AnchorController.tearDownPanelContent`) which is
        // our canonical "stop animating" trigger.
        //
        // All three drawing passes (stars, particles, ripples) share a
        // single `Canvas`. Each separate Canvas is its own SwiftUI view,
        // so the layout engine has to walk three nodes per frame; merging
        // them into one cuts that to a single node and a single
        // GraphicsContext per tick.
        TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
            Canvas { gc, size in
                drawStarfield(into: gc, size: size, now: context.date)
                drawParticles(into: gc, size: size, now: context.date)
                drawRipples(into: gc, now: context.date)
            }
            .allowsHitTesting(false)
        }
    }

    /// Ambient backdrop, switched by color scheme. Re-renders only when the
    /// user flips 白天/夜间 (light/dark) — not per frame — so it stays outside
    /// the timeline.
    ///
    /// - **Night (dark):** deep-space gradient, near-black. The starfield
    ///   and neon glows read against it exactly as before.
    /// - **Day (light):** a clear daytime sky (sky-blue → pale horizon) with
    ///   a soft warm sun glow in the top-trailing corner. The character
    ///   clips have transparent backgrounds, so they sit naturally on the
    ///   brighter sky; the starfield fades to faint daylight dust motes.
    @ViewBuilder
    private var ambientBackdrop: some View {
        if isDay {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.46, green: 0.69, blue: 0.93),
                        Color(red: 0.83, green: 0.90, blue: 0.98)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                // Soft sun glow, top-trailing.
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.95, blue: 0.80).opacity(0.85),
                        .clear
                    ],
                    center: .topTrailing, startRadius: 0, endRadius: 150
                )
                .blendMode(.plusLighter)
            }
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.10),
                    Color(red: 0.01, green: 0.01, blue: 0.04)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Layers

    // (Backdrop gradient + cursor halo were extracted out of the
    //  per-frame TimelineView path — see `ambientBackdrop` and
    //  `cursorHalo` layered directly in `body`. Only `starfield(now:)`
    //  stays inside the timeline because that's the layer that actually
    //  needs `now` to drive its twinkle.)

    /// Soft cyan halo following the cursor. Faint enough not to wash out
    /// the stars; just a subtle "your attention is here" cue.
    @ViewBuilder
    private var cursorHalo: some View {
        if let c = cursorPos {
            Circle()
                .fill(RadialGradient(
                    colors: [
                        CyberPalette.neonCyan.opacity(0.18),
                        CyberPalette.neonCyan.opacity(0.05),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0, endRadius: 70
                ))
                .frame(width: 160, height: 160)
                .blur(radius: 6)
                .position(c)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// Renders the star list into the shared `GraphicsContext` — drives
    /// per-star brightness from sin waves, boosts proximity to the
    /// cursor. Was previously its own `Canvas`; merged into the combined
    /// ambient Canvas so SwiftUI's layout engine sees one node, not three.
    private func drawStarfield(into context: GraphicsContext, size: CGSize, now: Date) {
        let t = now.timeIntervalSinceReferenceDate
        let cursor = cursorPos
        let boostRadius: CGFloat = 90
        let boostRadiusSq = boostRadius * boostRadius // skip sqrt in the hot loop

        // In daytime the "stars" become faint white dust motes drifting in
        // the sunlight — same positions + twinkle, but dimmed and
        // decolored so they don't read as night-sky stars on a bright sky.
        let dayMode = isDay
        let dayDim = 0.28

        for star in stars {
            let twinkle = 0.5 + 0.5 * sin(t * star.twinkleSpeed + star.twinklePhase)
            let pos = CGPoint(x: star.x * size.width, y: star.y * size.height)

            // Boost factor — falls off smoothly with distance from cursor.
            // Compare squared distances first so we only do `sqrt` for
            // the (small) subset of stars that are actually near the
            // cursor.
            var boost: Double = 0
            if let c = cursor {
                let dx = pos.x - c.x
                let dy = pos.y - c.y
                let dSq = dx * dx + dy * dy
                if dSq < boostRadiusSq {
                    boost = 1.0 - (sqrt(dSq) / boostRadius)
                }
            }

            var opacity = min(1.0, star.baseOpacity * twinkle * (1.0 + boost * 0.6))
            if dayMode { opacity *= dayDim }
            // Skip near-invisible stars entirely — at the bottom of the
            // sin wave they contribute nothing visible but still cost
            // two ellipse fills.
            if opacity < 0.04 { continue }
            let drawSize = star.size * CGFloat(1.0 + boost * 0.5)
            let drawColor = dayMode ? Color.white : star.color

            if drawSize > 1.7 {
                let glow = CGRect(
                    x: pos.x - drawSize * 1.4,
                    y: pos.y - drawSize * 1.4,
                    width: drawSize * 2.8,
                    height: drawSize * 2.8
                )
                context.fill(Path(ellipseIn: glow),
                             with: .color(drawColor.opacity(opacity * 0.30)))
            }
            let rect = CGRect(
                x: pos.x - drawSize / 2,
                y: pos.y - drawSize / 2,
                width: drawSize,
                height: drawSize
            )
            context.fill(Path(ellipseIn: rect),
                         with: .color(drawColor.opacity(opacity)))
        }
    }

    /// Click ripples — expanding cyan rings centered on the click point.
    /// One ring per click; lifetime ~1.2s. Usually empty (no ripples in
    /// flight) so the loop returns immediately.
    private func drawRipples(into context: GraphicsContext, now: Date) {
        guard !ripples.isEmpty else { return }
        var alive: [Ripple] = []
        for ripple in ripples {
            let elapsed = now.timeIntervalSince(ripple.bornAt)
            guard elapsed < ripple.lifetime else { continue }
            let t = elapsed / ripple.lifetime
            let radius = 6 + 90 * t
            let opacity = max(0, 0.65 * (1.0 - t))
            let rect = CGRect(
                x: ripple.origin.x - radius,
                y: ripple.origin.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(CyberPalette.neonCyan.opacity(opacity)),
                lineWidth: 1.4
            )
            alive.append(ripple)
        }
        if alive.count != ripples.count {
            DispatchQueue.main.async { ripples = alive }
        }
    }

    /// Static CRT-scanline overlay. Was previously a `GeometryReader` +
    /// `ForEach` of ~190 `Rectangle` views with a `withAnimation` driving
    /// `scanlineOffset` perpetually — that meant SwiftUI re-evaluated the
    /// view tree on every frame of the animation (60fps) just to slide
    /// stripes by 1px. The drift was barely visible at the 0.025 opacity
    /// the stripes already render at, so we drop the animation entirely
    /// and draw the static pattern in a single `Canvas`. Net change is
    /// imperceptible visually but huge for CPU.
    private var scanlines: some View {
        Canvas { context, size in
            let stripeHeight: CGFloat = 2
            let cycle = stripeHeight * 2
            let color = Color.white.opacity(0.025)
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: stripeHeight)
                context.fill(Path(rect), with: .color(color))
                y += cycle
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Animated character clip — fills the card edge-to-edge. Aspect
    /// mismatch between the 1:1.5 clip and the 1:1.9 card is handled by
    /// `.aspectRatio(.fill) + .clipped()` inside the player.
    ///
    /// The clips have alpha-channel transparent backgrounds (chroma-keyed
    /// from the AI's white BG at extraction time) so wherever the
    /// character isn't, the AvatarHero's drawn cyber backdrop shows
    /// through — no seams, no color mismatch.
    ///
    /// When the weather pill is shown we push the clip down a bit so her
    /// head clears the pill. The empty top region just shows more of the
    /// backdrop, which is what we want.
    private var character: some View {
        // Looping moods (idle / listening / walking / sleeping) play at
        // 12 fps — animation's classic "on twos" cadence (24fps cinema
        // sampled every other frame). Looks smooth, costs SwiftUI 25%
        // less per second than 16. One-shots stay at 16 because they
        // only run for ~5 seconds total, so the higher rate is a bounded
        // expense.
        let pack = packStore.selected
        return AnimatedAvatarPlayer(
            clip: pack.clip(for: playingMood.clipName),
            isLooping: playingMood.isLooping,
            fps: playingMood.isLooping ? pack.loopFps : pack.fps,
            verticalOffset: showWeather ? (compact ? 36 : 50) : 0,
            animDirectory: pack.animDirectory,
            onFinished: { handleOneShotFinished() }
        )
    }

    /// Slow neon-pink pulse drawn around the avatar while a `critical`
    /// event is on screen. Lives as a sibling to the corner accents,
    /// behind the weather overlay. Uses a `TimelineView` on a 6fps
    /// tick so the pulse is cheap — it's just a sin wave on the
    /// halo's opacity + scale, no per-pixel work.
    ///
    /// Color follows `EventLevelStyle.critical` (= `CyberPalette.neonPink`)
    /// so the pulse stays on-brand with the rest of the cyber
    /// vocabulary — system red would have stood out as foreign.
    private var cornerAccents: some View {
        VStack {
            HStack {
                HudBracket(corner: .topLeading)
                Spacer()
                HudBracket(corner: .topTrailing)
            }
            Spacer()
            HStack {
                HudBracket(corner: .bottomLeading)
                Spacer()
                HudBracket(corner: .bottomTrailing)
            }
        }
        .padding(compact ? 6 : 10)
        .allowsHitTesting(false)
    }

    private var weatherOverlay: some View {
        VStack {
            WeatherBubble(vm: weather)
                .padding(.top, compact ? 12 : 22)
            Spacer()
        }
    }

    /// Particle layer drawn into the shared ambient `GraphicsContext`.
    /// Usually empty (no particles in flight); the early-return makes
    /// that the cheap path.
    private func drawParticles(into context: GraphicsContext, size: CGSize, now: Date) {
        guard !particles.isEmpty else { return }
        var alive: [HeroParticle] = []
        for var p in particles {
            let elapsed = now.timeIntervalSince(p.bornAt)
            guard elapsed < p.lifetime else { continue }
            let t = elapsed / p.lifetime
            // Step constant matches the host TimelineView's 20 fps tick
            // rate.
            p.x += p.vx * (1.0 / 20.0)
            p.y += p.vy * (1.0 / 20.0)
            let opacity = max(0, 1.0 - t * 1.1)
            let pos = CGPoint(x: p.x, y: p.y)
            let symbolText = Text(Image(systemName: p.symbol))
                .font(.system(size: p.size, weight: .semibold))
                .foregroundStyle(p.color.opacity(opacity))
            context.draw(symbolText, at: pos)
            alive.append(p)
        }
        if alive.count != particles.count {
            DispatchQueue.main.async { particles = alive }
        }
    }

    // MARK: - Loops

    private func startPerpetualLoops() {
        // Star twinkle is driven by TimelineView in starfield().
        // Scanlines used to drift via `withAnimation(.linear.repeatForever)`
        // here, but that ran at the display's refresh rate (60fps) and
        // forced a SwiftUI re-evaluation each frame. The drift was nearly
        // invisible at 0.025 opacity, so we dropped it. Nothing else needs
        // a perpetual loop — keeping the function as a stub in case we
        // ever want to bring one back.
        _ = scanlineOffset // (silence unused-state warning if ever)
    }


    private func scheduleAutoSleep() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            guard !Task.isCancelled, mood == .idle, !autoSleeping else { return }
            autoSleeping = true
            playingMood = .sleeping
            withAnimation(.easeInOut(duration: 0.7)) {
                moodOpacity = 0.7
            }
            // Drip Z particles while sleeping.
            Task { @MainActor in
                while autoSleeping && !heroEvents.isListening {
                    spawnParticles(
                        count: 1,
                        symbol: "z.circle.fill",
                        color: CyberPalette.neonCyan.opacity(0.7),
                        sizeRange: 12...18,
                        upwardSpeed: 30...50,
                        lateralSpread: -8...8,
                        lifetime: 2.4,
                        originY: 100
                    )
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                }
            }
        }
    }

    private func wakeFromSleepIfNeeded() {
        guard autoSleeping else { return }
        autoSleeping = false
        withAnimation(.easeInOut(duration: 0.4)) {
            moodOpacity = 1.0
        }
    }

    // MARK: - Mood transitions

    private func handleMoodChange(_ new: HeroMood) {
        wakeFromSleepIfNeeded()
        // External `mood` change drops any in-flight one-shot.
        pendingOneShot = nil
        playingMood = new
        scheduleAutoSleep()
    }

    /// Bus-arriving one-shot. Drops the request when another one-shot is
    /// already playing, so e.g. a sync celebration arriving mid-greeting
    /// no longer cuts the greeting in half. Events that fire AFTER the
    /// in-flight one-shot finishes are processed normally — only the
    /// concurrent overlap is dropped.
    private func busFireOneShot(_ shot: HeroMood) {
        guard pendingOneShot == nil else { return }
        fireOneShot(shot)
    }

    /// Fire a one-shot reaction — play that clip once, then revert to the
    /// underlying `mood`. Pink star particles still pop on celebration so
    /// the success isn't silent; other reactions just swap to their clip.
    private func fireOneShot(_ shot: HeroMood) {
        wakeFromSleepIfNeeded()
        pendingOneShot = shot
        playingMood = shot

        if shot == .celebrating {
            spawnParticles(
                count: 7,
                symbol: "sparkle",
                color: CyberPalette.neonPink,
                sizeRange: 11...18,
                upwardSpeed: 60...110,
                lateralSpread: -50...50,
                lifetime: 1.2,
                originY: 90
            )
        }
    }

    /// Called by AnimatedAvatarPlayer when a one-shot finishes playing.
    /// Revert to the underlying loop mood.
    private func handleOneShotFinished() {
        guard pendingOneShot != nil else { return }
        pendingOneShot = nil
        playingMood = mood
    }

    /// Listening — sustain the listening clip while voice capture is on.
    private func setListening(_ on: Bool) {
        if on {
            wakeFromSleepIfNeeded()
            playingMood = .listening
        } else {
            playingMood = mood
        }
    }

    // MARK: - Click handling

    /// Tap on the avatar card → spawn a ripple at the click point and
    /// trigger a one-shot reaction. Three+ rapid clicks within 0.6s
    /// switch the reaction from "greeting" to "confused" — she gets
    /// poke-fatigued.
    private func handleClick(at point: CGPoint) {
        // Spawn a ripple ring.
        ripples.append(Ripple(id: UUID(), origin: point, bornAt: Date(), lifetime: 1.2))

        // Track recent clicks for the rapid-poke detector.
        let now = Date()
        recentClicks = recentClicks.filter { now.timeIntervalSince($0) < 0.6 }
        recentClicks.append(now)

        if recentClicks.count >= 3 {
            recentClicks.removeAll()
            fireOneShot(.confused)
        } else {
            fireOneShot(.greeting)
        }
    }

    // MARK: - Particle helpers

    private func spawnParticles(
        count: Int,
        symbol: String,
        color: Color,
        sizeRange: ClosedRange<CGFloat>,
        upwardSpeed: ClosedRange<CGFloat>,
        lateralSpread: ClosedRange<CGFloat>,
        lifetime: TimeInterval,
        originY: CGFloat
    ) {
        let now = Date()
        var fresh: [HeroParticle] = []
        for _ in 0..<count {
            fresh.append(HeroParticle(
                id: UUID(),
                x: CGFloat.random(in: 80...120),
                y: originY + CGFloat.random(in: -10...10),
                vx: CGFloat.random(in: lateralSpread),
                vy: -CGFloat.random(in: upwardSpeed),
                size: CGFloat.random(in: sizeRange),
                symbol: symbol,
                color: color,
                bornAt: now,
                lifetime: lifetime
            ))
        }
        particles.append(contentsOf: fresh)
    }
}

// MARK: - Ripple model

/// One click ripple — an expanding ring centered on `origin`. Drawn by
/// `rippleLayer`; auto-evicted once `bornAt + lifetime` is in the past.
private struct Ripple: Identifiable {
    let id: UUID
    var origin: CGPoint
    var bornAt: Date
    var lifetime: TimeInterval
}

// MARK: - Star model

private struct HeroStar {
    /// Normalized 0..1 position within the card.
    var x: Double
    var y: Double
    /// Render diameter in points.
    var size: CGFloat
    /// Peak brightness — twinkle scales between 0 and this.
    var baseOpacity: Double
    var color: Color
    /// Radians per second.
    var twinkleSpeed: Double
    /// Initial offset in the twinkle sin wave (so stars don't pulse in sync).
    var twinklePhase: Double

    static func random() -> HeroStar {
        let r = Double.random(in: 0...1)
        let color: Color
        if r < 0.85 {
            color = .white
        } else if r < 0.93 {
            color = CyberPalette.neonCyan
        } else {
            color = CyberPalette.neonPink
        }
        return HeroStar(
            x: Double.random(in: 0...1),
            y: Double.random(in: 0...1),
            size: CGFloat.random(in: 0.6...2.4),
            baseOpacity: Double.random(in: 0.45...0.95),
            color: color,
            twinkleSpeed: Double.random(in: 1.0...3.2),
            twinklePhase: Double.random(in: 0...(2 * .pi))
        )
    }
}

// MARK: - Particle model

private struct HeroParticle: Identifiable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var size: CGFloat
    var symbol: String
    var color: Color
    var bornAt: Date
    var lifetime: TimeInterval
}

// MARK: - Time of day palette

private enum TimeOfDay {
    static func palette(for date: Date) -> (topHalo: Color, bottomRim: Color) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<8:
            return (Color(red: 1.0, green: 0.65, blue: 0.45),
                    Color(red: 1.0, green: 0.40, blue: 0.55))
        case 8..<17:
            return (Color(red: 1.0, green: 0.30, blue: 0.75),
                    Color(red: 0.0, green: 0.85, blue: 1.0))
        case 17..<19:
            return (Color(red: 1.0, green: 0.40, blue: 0.55),
                    Color(red: 1.0, green: 0.55, blue: 0.30))
        case 19..<22:
            return (Color(red: 0.65, green: 0.35, blue: 0.95),
                    Color(red: 0.30, green: 0.55, blue: 1.0))
        default:
            return (Color(red: 0.45, green: 0.25, blue: 0.85),
                    Color(red: 0.20, green: 0.30, blue: 0.85))
        }
    }
}

// MARK: - Self chrome modifier

private struct SelfChromeModifier: ViewModifier {
    let enabled: Bool
    let compact: Bool

    func body(content: Content) -> some View {
        if enabled {
            let radius: CGFloat = compact ? 14 : 22
            content
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(CyberPalette.panelStroke, lineWidth: 1)
                )
        } else {
            content
        }
    }
}

// MARK: - HUD bracket

private struct HudBracket: View {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }
    var corner: Corner
    var length: CGFloat = 14
    var thickness: CGFloat = 1.5

    var body: some View {
        let color = CyberPalette.neonCyan.opacity(0.55)
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: thickness, height: length)
                .offset(x: vOffsetX, y: 0)
            Rectangle()
                .fill(color)
                .frame(width: length, height: thickness)
                .offset(x: 0, y: hOffsetY)
        }
        .frame(width: length, height: length)
    }

    private var vOffsetX: CGFloat {
        switch corner {
        case .topLeading, .bottomLeading: return -length/2 + thickness/2
        case .topTrailing, .bottomTrailing: return length/2 - thickness/2
        }
    }
    private var hOffsetY: CGFloat {
        switch corner {
        case .topLeading, .topTrailing: return -length/2 + thickness/2
        case .bottomLeading, .bottomTrailing: return length/2 - thickness/2
        }
    }
}
