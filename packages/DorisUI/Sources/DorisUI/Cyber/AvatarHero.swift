import SwiftUI
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the avatar is currently doing. Each case maps to a clip in the
/// active character pack (`Characters/<id>/anim/<clip>/`):
///
/// - **Loop clips**: idle, listening, sleeping — cycle forever.
/// - **One-shot clips**: greeting, alerted, celebrating — play once, then
///   automatically revert to the underlying loop mood.
public enum HeroMood: Equatable {
    case idle
    case greeting
    case alerted
    case listening
    case celebrating
    case sleeping

    /// Clip directory name, e.g. `"idle"` → frames at
    /// `<animDirectory>/idle/idle_0001.png …`.
    var clipName: String {
        switch self {
        case .idle:        return "idle"
        case .greeting:    return "greeting"
        case .alerted:     return "alerted"
        case .listening:   return "listening"
        case .celebrating: return "celebrating"
        case .sleeping:    return "idle"     // no dedicated clip yet
        }
    }

    var isLooping: Bool {
        switch self {
        case .idle, .listening, .sleeping: return true
        case .greeting, .alerted, .celebrating: return false
        }
    }
}

/// The animated character on its own: the desktop pet. Plays the active
/// pack's frame clips, reacts to `HeroEvents` (greet / celebrate / alert /
/// listen), dims into sleep after five idle minutes, carries the focus
/// (pomodoro) overlay, and freezes while its window can't be seen.
///
/// The host window owns click and drag; this view takes no gestures.
/// (It used to also be a decorated card — starfield, weather, HUD
/// brackets, click ripples — for the main window's sidebar and the old
/// dropdown. Those panes are gone, and so is all of that.)
public struct AvatarHero: View {
    var mood: HeroMood
    /// Tighter padding for the focus overlay, for small pets.
    var compact: Bool

    public init(mood: HeroMood = .idle, compact: Bool = false) {
        self.mood = mood
        self.compact = compact
    }

    @ObservedObject private var heroEvents = HeroEvents.shared
    @ObservedObject private var focus = FocusTimer.shared
    /// Active visual identity. Switching the selected pack swaps the
    /// character's frames live (the player keys its cache on the pack's
    /// anim directory, so the same mood name reloads new art).
    @ObservedObject private var packStore = CharacterPackStore.shared

    // MARK: - State

    /// What's actually playing right now. Distinct from `mood` (the param
    /// telling us the underlying loop) because one-shot reactions drive
    /// `playingMood` temporarily, then revert.
    @State private var playingMood: HeroMood = .idle
    /// One-shot hold — set to .greeting/.alerted/.celebrating when an
    /// event fires; cleared when the clip finishes playing.
    @State private var pendingOneShot: HeroMood?
    @State private var moodOpacity: Double = 1.0
    @State private var autoSleeping: Bool = false
    /// Host-window visibility (macOS occlusion). When the window is hidden /
    /// occluded / minimized / on another Space / display asleep, the clip
    /// freezes on one frame, so a pet nobody can see burns no CPU. The
    /// macOS `WindowVisibilityReader` flips it as occlusion changes; iOS
    /// leaves it true.
    @State private var isOnScreen: Bool = true

    // MARK: - Body

    public var body: some View {
        ZStack {
            character
            // Focus (pomodoro) overlay — task name + countdown on top of
            // the character. Nothing renders when there's no session.
            focusOverlay
        }
        .opacity(moodOpacity)
        .contentShape(Rectangle())
        // Report host-window occlusion → isOnScreen (drives the pause). Invisible.
        .background { visibilityProbe }
        .onAppear {
            playingMood = mood
            scheduleAutoSleep()
        }
        .onChange(of: mood) { _, new in handleMoodChange(new) }
        // Bus-driven one-shots respect any one-shot already in flight — a
        // greeting on window-open shouldn't get cut short by a sync
        // celebration or an arriving alert.
        .onChange(of: heroEvents.lastCelebration) { _, _ in busFireOneShot(.celebrating) }
        .onChange(of: heroEvents.lastGreeting)    { _, _ in busFireOneShot(.greeting) }
        .onChange(of: heroEvents.lastAlert)       { _, _ in busFireOneShot(.alerted) }
        .onChange(of: heroEvents.isListening)     { _, on in setListening(on) }
    }

    /// Looping moods play at the pack's loop rate (12 fps, animation's
    /// "on twos"); one-shots at its full rate — they only run a few
    /// seconds, so the higher rate is a bounded expense.
    private var character: some View {
        let pack = packStore.selected
        return AnimatedAvatarPlayer(
            clip: pack.clip(for: playingMood.clipName),
            isLooping: playingMood.isLooping,
            fps: playingMood.isLooping ? pack.loopFps : pack.fps,
            animDirectory: pack.animDirectory,
            paused: !isOnScreen,   // freeze the frame timer when the host is hidden
            onFinished: { handleOneShotFinished() }
        )
    }

    // MARK: - Focus (pomodoro) overlay

    /// Current-task highlight + countdown layered on top of the character.
    /// `running`/`resting` → a compact badge pinned near the bottom (so it
    /// doesn't cover the face). `finished` → the "next step" prompt. Renders
    /// nothing when there's no session, so idle avatars pay zero cost.
    @ViewBuilder
    private var focusOverlay: some View {
        if let s = focus.session {
            VStack {
                Spacer(minLength: 0)
                if s.phase == .finished {
                    focusFinishedPrompt(s)                 // has buttons → interactive
                } else {
                    focusRunningBadge(s)
                        .allowsHitTesting(false)            // display-only
                }
            }
            .padding(compact ? 8 : 12)
        }
    }

    private func focusAccent(_ s: FocusTimer.Session) -> Color {
        s.isRest ? CyberPalette.neonCyan : CyberPalette.neonPink
    }

    private func focusRunningBadge(_ s: FocusTimer.Session) -> some View {
        HStack(spacing: 6) {
            // Shared badge, so a paused session shows the same `II` here as
            // it does on the notch / edge tab.
            FocusRingBadge(diameter: 20, lineWidth: 2.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(s.displayTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(s.isPaused
                     ? L("Paused", "已暂停")
                     : CountdownRing.mmss(focus.remaining))
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(focusAccent(s).opacity(0.5), lineWidth: 0.7))
    }

    private func focusFinishedPrompt(_ s: FocusTimer.Session) -> some View {
        VStack(spacing: 6) {
            Text(s.isRest ? L("Break over", "休息结束") : L("Focus done", "专注结束"))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(focusAccent(s))
            Text(s.displayTitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 5) {
                // Keep going for another N minutes on the same task.
                focusExtendMenu
                focusPromptButton(L("Break", "休息"), "cup.and.saucer") { focus.startRest() }
                if focus.canComplete {
                    focusPromptButton(L("Done", "完成"), "checkmark") { focus.completeTask() }
                }
                // Always offer a plain way out — previously a completable
                // task had no exit that wasn't "mark it done".
                focusPromptButton(L("Exit", "退出"), "xmark") { focus.stop() }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(focusAccent(s).opacity(0.55), lineWidth: 0.7))
    }

    /// "再续" — rerun the same task for another N minutes. A menu rather than
    /// four more buttons, so the prompt stays small enough for the pet.
    private var focusExtendMenu: some View {
        Menu {
            ForEach([5, 15, 25], id: \.self) { m in
                Button(L("\(m) min", "\(m) 分钟")) { focus.adjust(minutes: m) }
            }
        } label: {
            focusPromptLabel(L("More", "再续"), "arrow.clockwise")
        }
        #if os(macOS)
        // `.borderlessButton` is macOS-only; without it the menu draws its
        // own chrome and swamps this tiny prompt.
        .menuStyle(.borderlessButton)
        #endif
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func focusPromptButton(_ title: String, _ icon: String,
                                   _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            focusPromptLabel(title, icon)
        }
        .buttonStyle(.plain)
    }

    private func focusPromptLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 8, weight: .medium))
        }
        .frame(minWidth: 34)
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
    }

    /// Invisible probe that watches the host NSWindow's occlusion state and
    /// updates `isOnScreen`. macOS only; iOS has no occlusion API (and the OS
    /// suspends background apps), so it stays a no-op there.
    @ViewBuilder
    private var visibilityProbe: some View {
        #if os(macOS)
        WindowVisibilityReader { visible in
            if visible != isOnScreen { isOnScreen = visible }
        }
        #else
        Color.clear
        #endif
    }

    // MARK: - Sleep and mood transitions

    private func scheduleAutoSleep() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            guard !Task.isCancelled, mood == .idle, !autoSleeping else { return }
            autoSleeping = true
            playingMood = .sleeping
            withAnimation(.easeInOut(duration: 0.7)) {
                moodOpacity = 0.7
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
    /// underlying `mood`.
    private func fireOneShot(_ shot: HeroMood) {
        wakeFromSleepIfNeeded()
        pendingOneShot = shot
        playingMood = shot
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
}

#if os(macOS)
/// Zero-size, invisible probe that reports its host `NSWindow`'s occlusion
/// state to SwiftUI. Place it in a `.background`. A window that is fully
/// covered, minimized, ordered-out, on another Space, or on a sleeping
/// display clears its `.visible` occlusion flag — AvatarHero uses that to
/// freeze all avatar animation while nobody can see it.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let v = TrackerView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            guard let window else { return }   // detached: leave last value
            report()
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.report() }
        }

        private func report() {
            onChange?(window?.occlusionState.contains(.visible) ?? false)
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
#endif
