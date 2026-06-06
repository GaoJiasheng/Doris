import AppKit
import SwiftUI
import DorisUI

/// Floating, click-through, top-most pill that displays the live state of a
/// voice capture session: "Listening…" while recording, the partial
/// transcript while speaking, and a brief "→ ChatGPT" hand-off animation
/// before disappearing. Lives across all spaces and full-screen apps so the
/// user sees it no matter what's frontmost.
///
/// Errors with a `Phase.ErrorAction` flip the panel from click-through to
/// interactive so the user can tap to fix the underlying problem (e.g.
/// open the Accessibility settings pane).
@MainActor
final class VoiceFloater {
    enum Phase: Equatable {
        case listening(partial: String)
        case sending(text: String, target: String)
        case error(message: String, action: ErrorAction? = nil)

        /// True for errors that carry a CTA. The panel uses this to flip
        /// `ignoresMouseEvents` so users can click the floater to open
        /// the Settings page that fixes the underlying problem.
        var isActionable: Bool {
            if case .error(_, let action) = self, action != nil { return true }
            return false
        }
    }

    /// Optional CTA attached to an error phase. When set, the floater
    /// becomes clickable and a "→ <label>" hint renders under the
    /// message. Currently only used for missing-Accessibility-permission,
    /// but the shape is generic so future permission errors (mic, screen
    /// recording, etc.) can plug in the same way.
    struct ErrorAction: Equatable {
        let label: String
        let url: URL
    }

    /// Convenience: build an error phase whose CTA opens the
    /// Accessibility settings pane. Single chokepoint so future callers
    /// don't have to remember the (long, fragile) URL.
    static func accessibilityError(message: String) -> Phase {
        .error(message: message, action: settingsAction(.accessibility))
    }

    /// Microphone-denied error → "Tap to open Settings" jumps to the
    /// Microphone privacy pane.
    static func micPermissionError(message: String) -> Phase {
        .error(message: message, action: settingsAction(.microphone))
    }

    /// Speech-recognition-denied error → jumps to the Speech Recognition
    /// privacy pane.
    static func speechPermissionError(message: String) -> Phase {
        .error(message: message, action: settingsAction(.speechRecognition))
    }

    /// Deep-link URLs for the System Settings privacy panes we care
    /// about. Apple's URL scheme is `x-apple.systempreferences:`
    /// followed by the bundle id of the prefpane (kept stable across
    /// versions; macOS Ventura+ rebranded Settings but the URLs work).
    private enum SettingsTarget {
        case accessibility, microphone, speechRecognition

        var url: URL {
            switch self {
            case .accessibility:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            case .speechRecognition:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
            }
        }
    }

    private static func settingsAction(_ target: SettingsTarget) -> ErrorAction {
        ErrorAction(
            label: NSLocalizedString("Tap to open Settings", comment: ""),
            url: target.url
        )
    }

    private var window: NSPanel?
    private let model = FloaterModel()

    func show(initial: Phase) {
        model.phase = initial
        if window == nil { build() }
        // Click-through when there's nothing to act on, intercept clicks
        // when the current phase is an actionable error. Toggling on
        // every show keeps the listening / sending phases overlay-only.
        window?.ignoresMouseEvents = !initial.isActionable
        positionAndDisplay()
    }

    func update(_ phase: Phase) {
        model.phase = phase
        window?.ignoresMouseEvents = !phase.isActionable
    }

    func hide(after delay: TimeInterval = 0.0) {
        let target = window
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            target?.orderOut(nil)
        }
    }

    private func build() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Default to click-through; flipped per-phase in `show`/`update`.
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: FloaterView(model: model))
        self.window = panel
    }

    private func positionAndDisplay() {
        guard let window else { return }
        let size = window.frame.size
        // Avoid the `NSScreen.screens.first!` force-unwrap — it bakes
        // this file's path into the runtime trap metadata. `guard let`
        // bails silently in the (effectively impossible) case of zero
        // screens; nothing to position against anyway.
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                    ?? NSScreen.main
                    ?? NSScreen.screens.first else {
            return
        }
        // Center horizontally near the top of the primary screen, just under
        // the menu bar so it reads as a system overlay.
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height - 36
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
}

@MainActor
private final class FloaterModel: ObservableObject {
    @Published var phase: VoiceFloater.Phase = .listening(partial: "")
}

private struct FloaterView: View {
    @ObservedObject var model: FloaterModel
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22, height: 22)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.black.opacity(0.78), Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.30, blue: 0.75).opacity(0.55),
                            Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.65)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .frame(width: 280, height: 64)
        .colorScheme(.dark)
        // Tap anywhere on the floater while it's an actionable error →
        // open the bundled URL (e.g. the Accessibility settings pane).
        // SwiftUI's `.onTapGesture` only fires when the host window has
        // `ignoresMouseEvents = false`, which `VoiceFloater.show/update`
        // toggles based on `phase.isActionable`.
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            if case .error(_, let action?) = model.phase {
                NSWorkspace.shared.open(action.url)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.phase {
        case .listening:
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0))
                .scaleEffect(pulse ? 1.10 : 0.90)
        case .sending:
            Image(systemName: "paperplane.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.75))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.20))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .listening(let partial):
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Listening…", "正在聆听…"))
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.75))
                Text(partial.isEmpty ? L("speak now", "请说话") : partial)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        case .sending(let text, let target):
            VStack(alignment: .leading, spacing: 1) {
                Text(L("→ \(target)", "→ \(target)"))
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.75).opacity(0.85))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        case .error(let message, let action):
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Voice error", "语音错误"))
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.20).opacity(0.9))
                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                // CTA hint — only renders when the error carries an
                // action. Looks like a tappable secondary line so the
                // user knows the whole pill is clickable.
                if let action {
                    Text("→ \(action.label)")
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.95))
                        .padding(.top, 1)
                }
            }
        }
    }
}
