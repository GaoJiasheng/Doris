import Foundation
import Combine
import SwiftUI

extension Notification.Name {
    /// "Open this note's editor." `object` is the note's `UUID`;
    /// `userInfo["subtask"]` optionally carries a checklist line's text, and
    /// `ChecklistEditorView` puts the caret on the matching row. Posted by
    /// the macOS app when the focus ring is clicked.
    public static let dorisOpenNote = Notification.Name("doris.openNote")
}

/// The single "what am I focused on right now" timer that the notch and the
/// avatar surface. Deliberately tiny — a focus/pomodoro highlighter, not a
/// stats tool: one active session at a time, no history.
///
/// The model is platform-neutral; the UI that reads it (notch ring, avatar
/// overlay, start entry points) is macOS-only. State lives in memory +
/// UserDefaults (survives relaunch) — no SwiftData/CloudKit schema change.
///
/// The countdown ticks at **1 Hz** (a single Timer that only runs while a
/// session is active), so surfacing it costs almost nothing — in the spirit
/// of the avatar/backdrop energy fixes.
@MainActor
public final class FocusTimer: ObservableObject {
    public static let shared = FocusTimer()

    public enum Phase: String, Codable, Sendable {
        case running    // counting down on a task
        case resting    // counting down a break
        case paused     // held; `pausedRemaining` carries the frozen clock
        case finished   // hit zero; waiting for the user's next step
    }

    public struct Session: Codable, Equatable, Sendable {
        public var noteID: UUID?
        public var title: String
        public var subtaskText: String?
        public var durationMin: Int
        public var endsAt: Date
        public var phase: Phase
        /// Seconds left at the moment of pausing. `endsAt` is meaningless
        /// while paused (wall-clock keeps moving) — resume rebuilds it from
        /// this. Nil unless `phase == .paused`.
        public var pausedRemaining: Int? = nil
        /// What the session was doing before it was paused, so resume goes
        /// back to `.running` for a task and `.resting` for a break.
        public var phaseBeforePause: Phase? = nil
        /// When this run was armed. Re-stamped by every start / restart /
        /// duration change (but NOT by pause/resume), so observers can tell
        /// "a new run began" from "the same run changed state" — iOS uses it
        /// to raise the full-screen dial. Optional so sessions persisted
        /// before this field existed still decode.
        public var startedAt: Date? = nil

        /// What to show as the "current thing" — the sub-task line if this is
        /// a sub-task focus, otherwise the note's title.
        public var displayTitle: String {
            if let s = subtaskText, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
            return title
        }
        public var totalSeconds: Int { max(1, durationMin * 60) }
        /// A break is never tied to a completable task. Checks the
        /// pre-pause phase too, so a paused break still reads as a break.
        public var isRest: Bool {
            phase == .resting || (phase == .paused && phaseBeforePause == .resting)
        }
        public var isPaused: Bool { phase == .paused }
        /// Still an active focus (running, resting, or held) — i.e. the ring
        /// should be on screen. False once finished / cleared.
        public var isActive: Bool { phase != .finished }
    }

    /// The active session (nil when idle).
    @Published public private(set) var session: Session?
    /// Whole seconds remaining (0 while finished / idle). Republished each second.
    @Published public private(set) var remaining: Int = 0

    private var timer: Timer?
    private static let key = "doris.focus.session"

    private init() { restore() }

    // MARK: - Public API

    /// Start (or replace) a focus session on a task or sub-task.
    public func start(noteID: UUID?, title: String, subtask: String?, minutes: Int) {
        beginSession(Session(
            noteID: noteID,
            title: title,
            subtaskText: subtask,
            durationMin: max(1, minutes),
            endsAt: Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60)),
            phase: .running
        ))
    }

    /// Start a short break (not tied to a task).
    public func startRest(minutes: Int = 5) {
        beginSession(Session(
            noteID: nil,
            title: L("Break", "休息"),
            subtaskText: nil,
            durationMin: max(1, minutes),
            endsAt: Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60)),
            phase: .resting
        ))
    }

    /// Re-run the just-finished session with the same task + duration.
    public func restart() {
        guard let s = session else { return }
        start(noteID: s.noteID, title: s.title, subtask: s.subtaskText, minutes: s.durationMin)
    }

    /// Hold the clock. `endsAt` is frozen into `pausedRemaining` because
    /// wall-clock time keeps advancing while paused.
    public func pause() {
        guard var s = session, s.phase == .running || s.phase == .resting else { return }
        timer?.invalidate(); timer = nil
        let rem = max(0, Int(ceil(s.endsAt.timeIntervalSinceNow)))
        s.phaseBeforePause = s.phase
        s.pausedRemaining = rem
        s.phase = .paused
        session = s
        remaining = rem
        persist()
        armBackgroundAlert()    // → cancels; a held clock must not fire
    }

    /// Resume from a pause — rebuild `endsAt` from the frozen remainder.
    public func resume() {
        guard var s = session, s.phase == .paused else { return }
        let rem = max(1, s.pausedRemaining ?? remaining)
        s.endsAt = Date().addingTimeInterval(TimeInterval(rem))
        s.phase = s.phaseBeforePause ?? .running
        s.pausedRemaining = nil
        s.phaseBeforePause = nil
        session = s
        persist()
        tick()
        startTimer()
        armBackgroundAlert()
    }

    public func togglePause() {
        guard let s = session else { return }
        s.phase == .paused ? resume() : pause()
    }

    /// Change the session's length (the 15/25/45 right-click action) and
    /// restart the clock at that duration, keeping the same task.
    public func adjust(minutes: Int) {
        guard let s = session else { return }
        let m = max(1, minutes)
        var next = s
        next.durationMin = m
        next.endsAt = Date().addingTimeInterval(TimeInterval(m * 60))
        // Re-arming a finished/paused session puts it back to work.
        next.phase = s.isRest ? .resting : .running
        next.pausedRemaining = nil
        next.phaseBeforePause = nil
        beginSession(next)
    }

    /// Mark the focused task/sub-task done (via `completeHandler`) and clear.
    public func completeTask() {
        if let s = session { FocusTimer.completeHandler?(s) }
        stop()
    }

    /// Clear the session entirely.
    public func stop() {
        timer?.invalidate(); timer = nil
        session = nil
        remaining = 0
        UserDefaults.standard.removeObject(forKey: Self.key)
        #if os(iOS)
        FocusNotifier.cancel()
        #endif
    }

    /// True when the current session is on a real note (so "完成" makes sense).
    public var canComplete: Bool { (session?.noteID) != nil }

    /// True when this note (optionally this sub-task) is the current focus —
    /// used by the checklist / row UI to highlight the active item.
    public func isFocused(noteID: UUID, subtask: String? = nil) -> Bool {
        guard let s = session, s.phase != .finished, s.noteID == noteID else { return false }
        if let sub = subtask { return s.subtaskText == sub }
        return true
    }

    // MARK: - App-wired hooks (keep DorisUI free of the mac notify/SwiftData machinery)

    /// Fired when a session hits zero — the macOS app posts a Doris banner
    /// ("专注结束: <task>") through its existing notify path.
    public static var notify: ((Session) -> Void)?
    /// Called by `completeTask()` — the macOS app marks the note done (main
    /// task) or ticks the matching checklist line (sub-task) via SwiftData.
    public static var completeHandler: ((Session) -> Void)?

    // MARK: - Timer

    private func beginSession(_ s: Session) {
        var s = s
        s.startedAt = Date()    // every arm is a new run (see `startedAt`)
        session = s
        persist()
        tick()          // set `remaining` right away
        startTimer()
        armBackgroundAlert()
    }

    /// iOS: keep the local "focus done" notification in sync with the clock.
    /// The in-process timer dies when the app suspends, so the alert has to be
    /// a scheduled notification. No-op on macOS (the app posts a banner from
    /// `FocusTimer.notify` and is never suspended).
    private func armBackgroundAlert() {
        #if os(iOS)
        guard let s = session, s.phase == .running || s.phase == .resting else {
            FocusNotifier.cancel()
            return
        }
        FocusNotifier.arm(
            after: Int(ceil(s.endsAt.timeIntervalSinceNow)),
            title: s.displayTitle,
            isRest: s.isRest
        )
        #endif
    }

    private func startTimer() {
        timer?.invalidate()
        // Common-mode so it keeps ticking during menu tracking / scrolling.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard var s = session else { remaining = 0; return }
        // Paused holds its frozen remainder; finished sits at zero.
        if s.phase == .paused { remaining = s.pausedRemaining ?? remaining; return }
        guard s.phase != .finished else { remaining = 0; return }
        let rem = Int(ceil(s.endsAt.timeIntervalSinceNow))
        if rem > 0 {
            if remaining != rem { remaining = rem }
        } else {
            remaining = 0
            s.phase = .finished
            session = s
            persist()
            timer?.invalidate(); timer = nil
            HeroEvents.shared.alert(minActivity: 0)
            FocusTimer.notify?(s)
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let s = session, let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(Session.self, from: data) else { return }
        switch s.phase {
        case .finished:
            // Keep showing the finished prompt from before the quit.
            session = s; remaining = 0
        case .paused:
            // Stays held across a relaunch — the frozen remainder is the
            // whole point, so don't compare `endsAt` to now.
            session = s; remaining = s.pausedRemaining ?? 0
        case .running, .resting:
            if s.endsAt.timeIntervalSinceNow > 0 {
                session = s; tick(); startTimer()   // resume
                armBackgroundAlert()                // re-arm (idempotent)
            } else {
                var f = s; f.phase = .finished       // elapsed while quit
                session = f; remaining = 0; persist()
            }
        }
    }
}
