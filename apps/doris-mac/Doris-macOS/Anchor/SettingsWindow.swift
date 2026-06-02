import AppKit
import SwiftUI
import DorisCore
import DorisUI

/// Stand-alone settings panel. Lives outside the menu-bar avatar so the
/// pickers and bindings table can be a regular floating window the user
/// can click around in.
///
/// Styling: matches the dropdown panel + main window — adaptive cyber
/// gradient (dark / light), no vibrancy, no HUD chrome. The previous
/// `.hudWindow` style mask is what gave the window that frosted-glass /
/// dark translucent look the user complained about.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSPanel?

    func show() {
        if let existing = window {
            existing.title = L("Doris · Settings", "Doris · 设置")
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSPanel(
            // Compact size — was 660pt tall with a lot of empty bottom
            // space. 560 fits the four sections snugly with breathing
            // room for one more binding row.
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            // Plain titled panel — no `.hudWindow` (that style mask
            // gave us the dark vibrancy / frosted-glass look).
            // `.fullSizeContentView` lets the SwiftUI content extend
            // under the title bar so our `CyberPalette.backdrop`
            // gradient fills the whole window including the title-bar
            // strip. Without this the titlebar would render as either
            // empty (with `titlebarAppearsTransparent = true`) or as
            // the system's default light-gray vibrancy bar.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.title = L("Doris · Settings", "Doris · 设置")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Solid window — let the SwiftUI backdrop (`CyberPalette.backdrop`)
        // paint the actual color so it follows Dark / Light theme. The
        // window itself is just a transparent titlebar host.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        // Hide the title text but keep the close button — titlebar
        // becomes a translucent strip over the gradient with just the
        // traffic-light buttons. (Title text on the cyber gradient
        // looks awkward; the window is small enough that "this is
        // settings" is implicit.)
        panel.titleVisibility = .hidden

        let rootView = SettingsRoot()
        let host = NSHostingController(rootView: rootView)
        host.view.wantsLayer = true
        // Strip any NSVisualEffectView SwiftUI / AppKit might layer
        // underneath. Defense in depth — the styleMask change should
        // already cover it.
        DispatchQueue.main.async { stripVisualEffects(from: host.view) }
        panel.contentViewController = host
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }

    func close() {
        window?.orderOut(nil)
    }
}

/// Recursively hide any `NSVisualEffectView` inside the host's view tree.
/// macOS sometimes inserts these as backing material for hosted SwiftUI
/// content; once hidden the cyber-gradient background paints unimpeded.
private func stripVisualEffects(from view: NSView) {
    for sub in view.subviews {
        if let vfx = sub as? NSVisualEffectView { vfx.isHidden = true }
        else { stripVisualEffects(from: sub) }
    }
}

/// Wrapper that paints the adaptive cyber backdrop behind the actual
/// settings content and applies the theme's color scheme to the whole
/// subtree. Pulled out so it can be re-rendered when theme changes.
private struct SettingsRoot: View {
    @ObservedObject private var theme = ThemeSettings.shared

    var body: some View {
        ZStack(alignment: .top) {
            // Same `CyberPalette.backdrop` the dropdown panel and main
            // window use — adaptive (dark = deep purple, light = cream),
            // honors `preferredColorScheme` further down.
            CyberPalette.backdrop
                .ignoresSafeArea()
            // Pad the top so the traffic-light buttons don't overlap
            // the first section. Title-bar buttons sit ~6pt down from
            // the top and are ~14pt tall, so 22pt clears them with a
            // little breathing room without wasting space.
            AppearanceSettingsView()
                .padding(.top, 22)
        }
        // Explicit frame is required: when SwiftUI is hosted via
        // NSHostingController inside an NSPanel, removing the frame
        // makes the gradient collapse to 0×0 and the ScrollView
        // shrinks to content size — the window ends up showing only
        // the title-bar strip. Match the panel's content rect.
        .frame(width: 540, height: 540)
        .preferredColorScheme(theme.mode.colorScheme)
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var settings = AppearanceSettings.shared
    @ObservedObject var voice = VoiceSettings.shared
    @ObservedObject var lang = LanguageSettings.shared
    @ObservedObject var theme = ThemeSettings.shared
    @ObservedObject var sync = SyncSettings.shared
    @ObservedObject var integrations = IntegrationsRegistry.shared
    @ObservedObject var avatarSettings = AvatarSettings.shared
    @ObservedObject var desktopPanel = DesktopPanelSettings.shared
    /// Toggled by the "Install CLI…" button on a .missingCLI integration
    /// row — presents the InstallCLIWizardView as a sheet so the user
    /// can finish the wizard without leaving Settings. On dismiss we
    /// re-poll the registry so the row flips out of .missingCLI
    /// automatically once the symlink is in place.
    @State private var showInstallWizard = false

    var body: some View {
        ScrollView {
            // Order: theme / language / appearance are the everyday
            // tweaks at the top. Integrations / Voice / Sync sit at
            // the bottom as the "set once, forget" infrastructure
            // tier — burying them keeps the scroll anchored on what
            // you actually touch each day.
            VStack(alignment: .leading, spacing: 14) {
                themeSection
                Divider().overlay(Color.primary.opacity(0.08))
                languageSection
                Divider().overlay(Color.primary.opacity(0.08))
                appearanceSection
                Divider().overlay(Color.primary.opacity(0.08))
                windowSection
                Divider().overlay(Color.primary.opacity(0.08))
                integrationsSection
                Divider().overlay(Color.primary.opacity(0.08))
                voiceSection
                Divider().overlay(Color.primary.opacity(0.08))
                syncSection
                // Anchored at the very bottom of the scroll: the build
                // identity. Tracks project.yml via Bundle.main so it
                // never goes stale.
                versionFooter
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .scrollContentBackground(.hidden)
        // Re-poll provider statuses every time the panel appears so
        // the user sees fresh "已注册" / "未注册" pills (e.g. after
        // editing ~/.claude/settings.json by hand outside Doris).
        .task { await integrations.refresh() }
        .sheet(isPresented: $showInstallWizard) {
            InstallCLIWizardView {
                showInstallWizard = false
                Task { await integrations.refresh() }
            }
        }
    }

    // MARK: - Sync

    /// Sync section — mirrors the iOS Settings → Sync tab. Status banner
    /// at the top reflects the same `SyncSettings.shared` state that
    /// drives the toolbar sync pill, so the two surfaces always agree.
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Sync", "同步"))
                .font(.headline)
                .foregroundStyle(.primary)

            SyncStatusBanner()

            HStack {
                Text(L("Use iCloud sync", "使用 iCloud 同步"))
                    .frame(width: 160, alignment: .leading)
                    .foregroundStyle(.primary)
                Toggle("", isOn: $sync.cloudKitEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Spacer()
            }

            HStack {
                Text(L("Auto-sync every 60s", "每 60 秒自动同步"))
                    .frame(width: 160, alignment: .leading)
                    .foregroundStyle(.primary)
                Toggle("", isOn: $sync.autoSyncEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                Spacer()
            }

            SyncNowRow()

            Text(L(
                "Sync Now performs a local save plus a CloudKit reachability check (account status + user record fetch). \"Last synced\" only updates when both succeed. Restart Doris after toggling iCloud for the change to take effect.",
                "立即同步会先本地保存,然后真实验证 iCloud 可达性(账号状态 + 拉取用户 record)。两步都成功才会刷新「上次同步」时间。切换 iCloud 后需重启 Doris 才会生效。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Integrations

    /// "应用集成" — show each registered IntegrationProvider as a row
    /// with current status + an action button. Bound to the shared
    /// `IntegrationsRegistry`, which already debounces filesystem
    /// reads to the explicit `refresh()` we call in `.task`.
    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("App integrations", "应用集成"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                if integrations.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Spacer()
            }
            Text(L(
                "Route task-completion notifications from Claude Code and Codex through Doris instead of the system Notification Center.",
                "把 Claude Code 和 Codex 的「任务完成」通知改走 Doris，绕过系统通知中心。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(integrations.providers, id: \.id) { provider in
                    integrationRow(provider)
                }
            }
        }
    }

    @ViewBuilder
    private func integrationRow(_ provider: any IntegrationProvider) -> some View {
        let status = integrations.statuses[provider.id] ?? .notApplicable
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: provider.iconSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 22, height: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(integrationSubtitle(provider: provider, status: status))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            integrationActionView(provider: provider, status: status)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Subtitle copy varies with status — bare summary for the .full
    /// happy paths, plus a clearer "manual setup" line for tiers that
    /// can't be auto-wired.
    private func integrationSubtitle(provider: any IntegrationProvider, status: IntegrationStatus) -> String {
        switch status {
        case .error(let msg):
            return msg
        case .missingCLI:
            return L("Doris CLI not installed — finish the install wizard first.",
                     "Doris CLI 还没装,请先完成安装向导。")
        default:
            break
        }
        // English brand summary lives on the provider; the Chinese mirror
        // lives here so localization stays in the UI layer.
        switch provider.id {
        case "claude-code":
            return L("Auto-write a Stop hook into ~/.claude/settings.json.",
                     "自动写入 Stop 钩子到 ~/.claude/settings.json。")
        case "codex":
            return L("Auto-wire Codex's notify hook in ~/.codex/config.toml.",
                     "自动接入 ~/.codex/config.toml 的 notify 钩子。")
        default:
            return provider.summary
        }
    }

    @ViewBuilder
    private func integrationActionView(provider: any IntegrationProvider, status: IntegrationStatus) -> some View {
        switch provider.supportTier {
        case .full:
            switch status {
            case .registered:
                HStack(spacing: 6) {
                    statusBadge(L("Registered", "已注册"), tint: CyberPalette.neonCyan)
                    Button(L("Unregister", "解除")) {
                        Task { try? await integrations.unregister(provider) }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.primary.opacity(0.65))
                }
            case .missingCLI:
                Button(L("Install CLI…", "安装 CLI…")) {
                    // Reuse the existing FirstRun wizard as a sheet —
                    // it already handles symlinking into /usr/local/bin
                    // or ~/.local/bin. On dismiss we refresh and the
                    // row flips to "未注册" so the user can click
                    // Register without leaving Settings.
                    showInstallWizard = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .notRegistered, .notApplicable:
                Button(L("Register", "注册")) {
                    Task { try? await integrations.register(provider) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .error:
                Button(L("Retry", "重试")) {
                    Task { await integrations.refresh() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .manual:
            HStack(spacing: 6) {
                statusBadge(L("Manual", "手动配置"), tint: .primary.opacity(0.55))
                if let url = provider.tutorialURL {
                    Button(L("Tutorial →", "查看教程 →")) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(CyberPalette.neonCyan)
                }
            }

        case .unsupported:
            statusBadge(L("Not supported", "暂不支持"), tint: .primary.opacity(0.4))
        }
    }

    private func statusBadge(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.15))
            )
            .overlay(
                Capsule().stroke(tint.opacity(0.45), lineWidth: 0.5)
            )
            .foregroundStyle(tint)
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Theme", "主题"))
                .font(.headline)
                .foregroundStyle(.primary)
            HStack {
                Text(L("Mode", "模式"))
                    .frame(width: 110, alignment: .leading)
                    .foregroundStyle(.primary)
                Picker("", selection: $theme.mode) {
                    ForEach(ThemeSettings.Mode.allCases) { m in
                        Label(m.displayName, systemImage: m.iconName).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 240, alignment: .leading)
                Spacer()
                ThemeToggleButton()
            }
            Text(L(
                "Dark = deep purple cyber backdrop. Light = soft cream with the same neon accents. Click the sun/moon button anywhere in the app for a one-click flip.",
                "深色为赛博紫黑底,浅色为奶油色,两种都保留霓虹粉青配色。任何位置的太阳/月亮按钮都能一键切换。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Language", "语言"))
                .font(.headline)
                .foregroundStyle(.primary)
            HStack {
                Text(L("Display", "显示"))
                    .frame(width: 110, alignment: .leading)
                    .foregroundStyle(.primary)
                Picker("", selection: $lang.mode) {
                    ForEach(LanguageSettings.Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 240, alignment: .leading)
                Spacer()
            }
            Text(L(
                "Switch the UI between English and Chinese.",
                "在英文和中文之间切换界面显示。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Voice", "语音"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Toggle(isOn: $voice.enabled) {
                    Text(L("Enabled", "启用"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 6) {
                bindingsHeader
                ForEach($voice.bindings) { $binding in
                    BindingRow(binding: $binding) {
                        voice.removeBinding(id: binding.id)
                    }
                    .disabled(!voice.enabled)
                }

                HStack {
                    Button {
                        voice.addBinding()
                    } label: {
                        Label(L("Add binding", "新增绑定"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!voice.enabled || voice.bindings.count >= VoiceSettings.TriggerKey.allCases.count)
                    Spacer()
                }
                .padding(.top, 4)
            }

            Text(L(
                "Hold a trigger key, speak, release. Doris transcribes locally with Apple Speech, then activates the chosen app and pastes (with optional auto-submit). Press Esc anytime to abort. First use prompts for Microphone, Speech Recognition, Input Monitoring, and Accessibility.",
                "按住触发键说话,松开后 Doris 用 Apple Speech 本地转写,自动前置目标 App 并粘贴(可选自动回车)。任何时候按 Esc 可终止录音。首次使用会逐步请求麦克风、语音识别、输入监听及辅助功能权限。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bindingsHeader: some View {
        HStack(spacing: 8) {
            Text(L("Trigger", "触发键")).frame(width: 110, alignment: .leading)
            Text(L("Language", "语言")).frame(width: 90, alignment: .leading)
            Text(L("Send to", "发送给")).frame(width: 130, alignment: .leading)
            Text(L("Submit", "回车")).frame(width: 50, alignment: .leading)
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.primary.opacity(0.5))
        .padding(.bottom, 2)
    }

    // MARK: - Version footer

    /// Compact build-identity strip at the bottom of the settings
    /// scroll. Reads CFBundleShortVersionString + CFBundleVersion via
    /// `Bundle.main` so it stays in lockstep with `project.yml` —
    /// avoids the "iOS Settings still says 0.7.0" stale-string bug.
    private var versionFooter: some View {
        HStack {
            Spacer()
            Text("Doris " + Self.appVersionString)
                .font(.caption2.monospaced())
                .foregroundStyle(.primary.opacity(0.35))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Appearance

    // MARK: - Window (avatar + desktop panel)

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Window", "窗口"))
                .font(.headline)
                .foregroundStyle(.primary)

            Toggle(isOn: Binding(get: { avatarSettings.avatarVisible },
                                 set: { avatarSettings.avatarVisible = $0 })) {
                Text(L("Show avatar", "显示小姑娘")).font(.subheadline)
            }
            .toggleStyle(.switch)

            Toggle(isOn: Binding(get: { desktopPanel.visible },
                                 set: { $0 ? DesktopPanelController.shared.show()
                                           : DesktopPanelController.shared.hide() })) {
                Text(L("Desktop panel", "桌面面板")).font(.subheadline)
            }
            .toggleStyle(.switch)

            Text(L(
                "The desktop panel floats a pinned + today summary on your desktop. To stick a single note, right-click it → Stick to desktop.",
                "桌面面板会在桌面上浮出「置顶 + 今日」的汇总。把单条笔记贴到桌面:右键那条笔记 →「贴到桌面」。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Appearance", "外观"))
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("Background opacity", "背景不透明度"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(settings.backgroundOpacity * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Slider(value: $settings.backgroundOpacity, in: 0.30 ... 1.0)
            }

            Text(L(
                "On the notch extension (top edge of a notched display) the avatar always renders as solid black so it fuses with the real notch — this slider has no effect there. On every other edge, the avatar background uses this opacity.",
                "在刘海扩展形态(带刘海屏幕的顶部)下,头像始终渲染为纯黑以与真刘海融合,此滑块无效。其它边缘下,头像背景采用该不透明度。"
            ))
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One row in the bindings table.
private struct BindingRow: View {
    @Binding var binding: VoiceBinding
    let onDelete: () -> Void
    @ObservedObject private var lang = LanguageSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $binding.triggerKey) {
                ForEach(VoiceSettings.TriggerKey.allCases) { k in
                    Text(k.displayName).tag(k)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 110)

            Picker("", selection: $binding.language) {
                ForEach(VoiceSettings.VoiceLanguage.allCases) { l in
                    Text(l.displayName).tag(l)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 90)

            Picker("", selection: $binding.provider) {
                ForEach(VoiceSettings.Provider.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            Toggle("", isOn: $binding.autoSubmit)
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 50, alignment: .leading)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help(L("Remove this binding", "删除此绑定"))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sync status banner

/// Status card at the top of the Sync section. Mirrors the iOS Settings
/// → Sync banner and the toolbar sync pill — same `SyncSettings.shared`
/// state, four mutually exclusive variants: in-sync (cyan checkmark),
/// error (red triangle + full message), local-only (muted slash), and
/// first-run "never synced".
private struct SyncStatusBanner: View {
    @ObservedObject private var sync = SyncSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var nowTick = Date()
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let hasError = sync.lastSyncError != nil
        let accent: Color =
            hasError ? .red :
            !sync.cloudKitEnabled ? Color.primary.opacity(0.45) :
            CyberPalette.neonCyan

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: bannerIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasError ? .red : .primary)
                Text(bannerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(hasError ? 0.45 : 0.18), lineWidth: 0.7)
        )
        .onReceive(tickTimer) { nowTick = $0 }
    }

    private var bannerIcon: String {
        if sync.lastSyncError != nil { return "exclamationmark.icloud.fill" }
        if !sync.cloudKitEnabled     { return "icloud.slash" }
        if sync.lastSyncedAt == nil  { return "icloud" }
        return "checkmark.icloud.fill"
    }

    private var bannerTitle: String {
        if sync.lastSyncError != nil { return L("Sync failed", "同步失败") }
        if !sync.cloudKitEnabled     { return L("iCloud sync is off", "iCloud 同步未启用") }
        if sync.lastSyncedAt == nil  { return L("Not synced yet", "尚未同步") }
        return L("In sync with iCloud", "已与 iCloud 同步")
    }

    private var bannerSubtitle: String {
        if let err = sync.lastSyncError { return err }
        if !sync.cloudKitEnabled {
            return L(
                "Notes stay on this Mac. Toggle iCloud on below to mirror to other devices.",
                "笔记仅保存在本机。下方开启 iCloud 即可与其他设备同步。"
            )
        }
        if sync.lastSyncedAt == nil {
            return L("Click Sync Now below to start a sync.",
                     "点击下方「立即同步」开始第一次同步。")
        }
        return lastSyncedLabel
    }

    private var lastSyncedLabel: String {
        guard let last = sync.lastSyncedAt else { return "" }
        _ = nowTick
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return L("Last synced ", "上次同步 ")
            + f.localizedString(for: last, relativeTo: Date())
    }
}

// MARK: - Sync Now row

/// Manual sync button + live last-synced label, side by side. Same
/// behaviour as the iOS Settings → Sync row: tap fires
/// `AppCommands.syncNow`, the spinner runs for 1.2s while the actor
/// performs the local save + CloudKit reachability probe, then the
/// "Last synced" label updates from `SyncSettings.shared`.
private struct SyncNowRow: View {
    @ObservedObject private var sync = SyncSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var isSyncing = false
    @State private var nowTick = Date()
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            Button { runManualSync() } label: {
                HStack(spacing: 6) {
                    if isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isSyncing
                         ? L("Syncing…", "同步中…")
                         : L("Sync Now", "立即同步"))
                }
            }
            .disabled(isSyncing)
            Spacer()
            Text(lastSyncedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onReceive(tickTimer) { nowTick = $0 }
    }

    private var lastSyncedLabel: String {
        guard let last = sync.lastSyncedAt else {
            return L("Never synced yet", "尚未同步")
        }
        _ = nowTick
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return L("Last synced ", "上次同步 ")
            + f.localizedString(for: last, relativeTo: Date())
    }

    private func runManualSync() {
        isSyncing = true
        AppCommands.syncNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isSyncing = false
        }
    }
}
