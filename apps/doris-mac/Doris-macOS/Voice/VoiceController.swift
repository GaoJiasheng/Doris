import AppKit
import Foundation
import Combine
import DorisIPC
import DorisUI

/// Top-level coordinator. Listens to all configured trigger keys, and on a
/// long-press → release cycle:
///
/// 1. Looks up the matching `VoiceBinding` by keyCode.
/// 2. Starts a speech-recognizer in that binding's language.
/// 3. On release, hands the transcript to `AppRouter` aimed at the
///    binding's provider, with the binding's auto-submit preference.
///
/// Only one recording is active at a time. If a second trigger key starts
/// while the first is still held, it's ignored until the active one ends.
@MainActor
final class VoiceController {
    private let hotkey = HotkeyEngine()
    private let floater = VoiceFloater()
    private let appRouter = AppRouter()

    private var bindingsByKey: [UInt16: VoiceBinding] = [:]
    private var recognizer: SpeechRecognizer?
    private var activeBinding: VoiceBinding?
    private var settingsCancellables = Set<AnyCancellable>()
    /// One-shot guard for `SpeechRecognizer.requestAuthorization()`.
    /// Without it, every hotkey trigger spawns a fresh `Task` that
    /// re-fires the system mic prompt — if the user dismisses (rather
    /// than answers) the prompt, the next press queues another one,
    /// and a held / rapidly-tapped hotkey causes runaway prompts.
    /// Set true on dispatch, cleared in `defer` when the task finishes.
    private var authorizationRequestInFlight = false
    /// Global ESC key monitor — only registered while a recording is in
    /// flight, so Escape is a universal "abort" for users who can't
    /// re-trigger the modifier release (e.g. their keyboard is sending
    /// stuck modifier flags, or they want to bail on a long dictation
    /// without sending). Cleared when recording ends.
    private var escapeMonitor: Any?

    init() {
        wireHotkey()
        observeSettings()
        applyBindings(VoiceSettings.shared.bindings)
    }

    func start() {
        guard VoiceSettings.shared.enabled else { return }
        hotkey.start()
    }

    func stop() {
        hotkey.stop()
    }

    // MARK: - Wire-up

    private func wireHotkey() {
        hotkey.onLongPressStart = { [weak self] kc in
            Task { @MainActor in self?.beginRecording(forKeyCode: kc) }
        }
        hotkey.onLongPressEnd = { [weak self] kc in
            Task { @MainActor in await self?.endRecording(forKeyCode: kc) }
        }
    }

    private func observeSettings() {
        VoiceSettings.shared.$bindings
            .sink { [weak self] list in
                self?.applyBindings(list)
            }
            .store(in: &settingsCancellables)

        VoiceSettings.shared.$enabled
            .sink { [weak self] enabled in
                if enabled { self?.hotkey.start() } else { self?.hotkey.stop() }
            }
            .store(in: &settingsCancellables)
    }

    private func applyBindings(_ list: [VoiceBinding]) {
        // Last write wins on collisions — UI prevents them in practice.
        var map: [UInt16: VoiceBinding] = [:]
        for b in list { map[b.triggerKey.keyCode] = b }
        bindingsByKey = map
        hotkey.setWatchedKeyCodes(Set(map.keys))
    }

    // MARK: - Recording lifecycle

    private func beginRecording(forKeyCode kc: UInt16) {
        DorisLog.voice.info("hotkey long-press fired keyCode=\(kc, privacy: .public)")
        guard let binding = bindingsByKey[kc] else {
            DorisLog.voice.notice("no binding for keyCode \(kc, privacy: .public)")
            return
        }
        guard activeBinding == nil else {
            DorisLog.voice.notice("another binding already active — ignoring")
            return
        }

        let auth = SpeechRecognizer.currentAuthorization()
        if auth != .granted {
            handleMissingAuthorization(auth)
            return
        }

        let r = SpeechRecognizer(locale: binding.language.locale)
        r.onPartial = { [weak self] partial in
            self?.floater.update(.listening(partial: partial))
        }
        do {
            try r.start()
            recognizer = r
            activeBinding = binding
            HeroEvents.shared.isListening = true
            floater.show(initial: .listening(partial: ""))
            armEscapeAbortMonitor()
            DorisLog.voice.info("recorder started for binding=\(binding.id.uuidString, privacy: .public) lang=\(binding.language.rawValue, privacy: .public) provider=\(binding.provider.rawValue, privacy: .public)")
        } catch {
            recognizer = nil
            DorisLog.voice.error("recorder start failed: \(error.localizedDescription, privacy: .public)")
            showError(message: error.localizedDescription, autoDismiss: 2.5)
        }
    }

    private func endRecording(forKeyCode kc: UInt16) async {
        guard let binding = activeBinding, binding.triggerKey.keyCode == kc, let r = recognizer else {
            return
        }
        activeBinding = nil
        recognizer = nil
        HeroEvents.shared.isListening = false
        disarmEscapeAbortMonitor()

        let result = await r.stop()
        DorisLog.voice.info("transcript len=\(result.text.count, privacy: .public): \(result.text, privacy: .public)")
        guard !result.text.isEmpty else {
            floater.hide(after: 0.15)
            return
        }

        floater.update(.sending(text: result.text, target: binding.provider.displayName))
        do {
            try await appRouter.send(text: result.text, to: binding.provider, autoSubmit: binding.autoSubmit)
            DorisLog.voice.info("router send ok")
            HeroEvents.shared.celebrate()
            floater.hide(after: 0.6)
        } catch {
            DorisLog.voice.error("router send failed: \(error.localizedDescription, privacy: .public)")
            // Surface accessibility-missing as an actionable banner —
            // user taps once and lands directly on the Privacy settings
            // pane where they can flip Doris's toggle on. Generic
            // errors keep the old plain banner.
            if case AppRouter.RouterError.accessibilityNotGranted = error {
                let phase = VoiceFloater.accessibilityError(
                    message: L("Doris needs Accessibility permission to paste.",
                               "Doris 需要辅助功能权限来粘贴。"))
                floater.show(initial: phase)
                // Longer dismiss so the user has time to read + tap.
                floater.hide(after: 8.0)
            } else {
                showError(message: error.localizedDescription, autoDismiss: 3.0)
            }
        }
    }

    // MARK: - Cancel

    /// Universal abort path. Called from the Esc key while a recording is
    /// in flight, or programmatically (UI cancel button, IPC). Tears
    /// down the recognizer, hides the floater, and discards whatever was
    /// captured — nothing gets sent to the provider.
    func cancelRecording() {
        guard let r = recognizer else { return }
        DorisLog.voice.notice("recording cancelled by user")
        activeBinding = nil
        recognizer = nil
        HeroEvents.shared.isListening = false
        disarmEscapeAbortMonitor()
        Task { @MainActor in
            _ = await r.stop()  // discard transcript
            floater.hide(after: 0)
        }
    }

    /// Watch for the Esc key while recording. Both global (other app
    /// focused) and local (Doris focused) so Esc works no matter where
    /// the user is when they realize they want to bail.
    private func armEscapeAbortMonitor() {
        guard escapeMonitor == nil else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 = kVK_Escape
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.cancelRecording() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.cancelRecording() }
                return nil  // swallow ESC so it doesn't propagate
            }
            return event
        }
        escapeMonitor = (global, local)
    }

    private func disarmEscapeAbortMonitor() {
        if let pair = escapeMonitor as? (Any?, Any?) {
            if let g = pair.0 { NSEvent.removeMonitor(g) }
            if let l = pair.1 { NSEvent.removeMonitor(l) }
        }
        escapeMonitor = nil
    }

    private func showError(message: String, autoDismiss: TimeInterval) {
        floater.show(initial: .error(message: message))
        floater.hide(after: autoDismiss)
    }

    /// Surface a permission-missing state to the user without spamming
    /// system prompts. There are two cases:
    ///
    /// - **notYetDetermined**: user hasn't been asked yet. Fire the
    ///   system prompt exactly ONCE (gated by `authorizationRequestInFlight`)
    ///   so rapid hotkey presses don't queue a stack of dialogs.
    /// - **denied / restricted**: prompt won't show again no matter how
    ///   many times we call `requestAuthorization`. Surface an
    ///   actionable banner with a deep-link to the right Privacy pane
    ///   so a tap lands the user directly on the toggle they need.
    private func handleMissingAuthorization(_ auth: SpeechRecognizer.Authorization) {
        switch auth {
        case .granted:
            return // shouldn't reach
        case .notYetDetermined:
            // Fire the system prompt exactly once. Subsequent presses
            // are no-ops until the user responds; that's the whole point
            // of the in-flight flag — otherwise queued prompts read as
            // an "infinite loop".
            guard !authorizationRequestInFlight else { return }
            authorizationRequestInFlight = true
            Task {
                defer { authorizationRequestInFlight = false }
                _ = await SpeechRecognizer.requestAuthorization()
            }
            showError(
                message: L("Requesting permission… answer the system prompt, then press the hotkey again.",
                           "正在请求权限,请在系统弹窗中选择,然后再次按下热键。"),
                autoDismiss: 4.0)
        case .deniedMicrophone:
            let phase = VoiceFloater.micPermissionError(
                message: L("Doris needs microphone access.",
                           "Doris 需要麦克风权限。"))
            floater.show(initial: phase)
            floater.hide(after: 8.0)
        case .deniedSpeech:
            let phase = VoiceFloater.speechPermissionError(
                message: L("Doris needs Speech Recognition access.",
                           "Doris 需要语音识别权限。"))
            floater.show(initial: phase)
            floater.hide(after: 8.0)
        case .restricted:
            showError(
                message: L("Speech recognition is restricted on this Mac.",
                           "本机已限制语音识别。"),
                autoDismiss: 3.0)
        }
    }
}
