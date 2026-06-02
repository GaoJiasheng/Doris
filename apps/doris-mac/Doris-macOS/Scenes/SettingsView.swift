import SwiftUI
import SwiftData
import AppKit
import DorisCore
import DorisIPC
import DorisUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var theme = ThemeSettings.shared
    @ObservedObject private var avatarSettings = AvatarSettings.shared
    @Query private var settingsQuery: [UserSettings]

    private var settings: UserSettings {
        if let existing = settingsQuery.first { return existing }
        let new = UserSettings()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        ZStack {
            CyberPalette.backdrop
                .ignoresSafeArea()
            TabView {
                generalTab
                    .tabItem { Label(L("General", "通用"), systemImage: "gear") }
                syncTab
                    .tabItem { Label(L("Sync", "同步"), systemImage: "icloud.fill") }
                recentlyDeletedTab
                    .tabItem { Label(L("Recently Deleted", "最近删除"), systemImage: "trash") }
                sidebarTab
                    .tabItem { Label(L("Sidebar", "侧栏"), systemImage: "sidebar.right") }
                shortcutTab
                    .tabItem { Label(L("Shortcuts", "快捷键"), systemImage: "keyboard") }
                cliTab
                    .tabItem { Label(L("CLI", "命令行"), systemImage: "terminal") }
            }
            .scrollContentBackground(.hidden)
            .padding()
        }
        .frame(width: 480, height: 460)
        .preferredColorScheme(theme.mode.colorScheme)
        .background(SettingsWindowOpacityFix())
    }

    private var generalTab: some View {
        Form {
            Picker(L("Theme", "主题"), selection: themeBinding) {
                ForEach(DorisTheme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle(L("Show hex color preview", "显示十六进制颜色预览"), isOn: showHexColorPreview)
            Toggle(L("Auto-backup daily", "每日自动备份"), isOn: autoBackupEnabled)
            // Default visibility of the cyber-girl avatar pane (main
            // window sidebar + menu-bar dropdown). Can also be toggled
            // live from the dropdown header / sidebar collapse button.
            Toggle(L("Show avatar", "显示小姑娘"),
                   isOn: Binding(get: { avatarSettings.avatarVisible },
                                 set: { avatarSettings.avatarVisible = $0 }))
            // Version row — reads CFBundleShortVersionString +
            // CFBundleVersion via Bundle.main so it tracks
            // project.yml without manual touch-ups.
            LabeledContent(L("Version", "版本")) {
                Text(Self.appVersionString)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }

    /// Sync tab — controls iCloud-backed CloudKit mirroring + manual
    /// sync. The CloudKit toggle is sticky (next launch) and shows a
    /// "restart required" hint because SwiftData binds the configuration
    /// at container init time.
    private var syncTab: some View {
        SyncSettingsTab()
    }

    /// Recently Deleted tab — shows archived notes so the user can
    /// restore or permanently delete them.
    private var recentlyDeletedTab: some View {
        MacRecentlyDeletedTab()
    }

    private var sidebarTab: some View {
        Form {
            Picker(L("Edge", "边缘"), selection: sidebarEdge) {
                Text(L("Left", "左")).tag(SidebarEdge.left)
                Text(L("Right", "右")).tag(SidebarEdge.right)
            }
            HStack {
                Text(L("Width", "宽度"))
                Slider(value: sidebarWidth, in: 240...520, step: 10)
                Text("\(Int(settings.sidebarWidth)) px")
            }
            Toggle(L("Hot Side enabled", "启用边缘热区"), isOn: hotSideEnabled)
            Toggle(L("Open Bar visible", "显示打开栏"), isOn: openBarVisible)
            Toggle(L("Pinned across spaces", "跨桌面置顶"), isOn: pinnedAcrossSpaces)
            Picker(L("Notch behavior", "刘海行为"), selection: notchBehavior) {
                ForEach(NotchBehavior.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var shortcutTab: some View {
        Form {
            KeyboardShortcuts.Recorder(L("Toggle sidebar", "切换侧栏"), name: .toggleSidebar)
            KeyboardShortcuts.Recorder(L("Toggle notch", "切换刘海"), name: .toggleNotch)
            KeyboardShortcuts.Recorder(L("Open events", "打开事件"), name: .openEvents)
        }
        .scrollContentBackground(.hidden)
    }

    private var cliTab: some View {
        Form {
            HStack {
                Text(L("CLI installed at", "CLI 安装位置"))
                Spacer()
                Text(settings.cliInstalledAt ?? L("(not installed)", "(未安装)"))
                    .foregroundStyle(.secondary)
            }
            Text(L("Allowed source app IDs", "允许的来源应用 ID"))
                .font(.headline)
            Text(settings.cliSourceAllowlist.joined(separator: ", "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .scrollContentBackground(.hidden)
    }

    // Bindings backing onto the persisted UserSettings row.
    // Renamed from `theme` to `themeBinding` so it doesn't collide with the
    // top-level `@ObservedObject private var theme = ThemeSettings.shared`
    // we observe to react to live theme switches.
    private var themeBinding: Binding<DorisTheme> {
        Binding(get: { settings.theme }, set: { settings.theme = $0 })
    }
    private var sidebarEdge: Binding<SidebarEdge> {
        Binding(get: { settings.sidebarEdge }, set: { settings.sidebarEdge = $0 })
    }
    private var notchBehavior: Binding<NotchBehavior> {
        Binding(get: { settings.notchBehavior }, set: { settings.notchBehavior = $0 })
    }
    private var sidebarWidth: Binding<Double> {
        Binding(get: { settings.sidebarWidth }, set: { settings.sidebarWidth = $0 })
    }
    private var hotSideEnabled: Binding<Bool> {
        Binding(get: { settings.hotSideEnabled }, set: { settings.hotSideEnabled = $0 })
    }
    private var openBarVisible: Binding<Bool> {
        Binding(get: { settings.openBarVisible }, set: { settings.openBarVisible = $0 })
    }
    private var pinnedAcrossSpaces: Binding<Bool> {
        Binding(get: { settings.pinnedAcrossSpaces }, set: { settings.pinnedAcrossSpaces = $0 })
    }
    private var showHexColorPreview: Binding<Bool> {
        Binding(get: { settings.showHexColorPreview }, set: { settings.showHexColorPreview = $0 })
    }
    private var autoBackupEnabled: Binding<Bool> {
        Binding(get: { settings.autoBackupEnabled }, set: { settings.autoBackupEnabled = $0 })
    }
}

/// macOS Sync settings tab — the user-facing surface for CloudKit + auto
/// sync controls. Lives in its own struct so `SyncSettings.shared` can be
/// observed without ballooning the parent's body.
private struct SyncSettingsTab: View {
    @ObservedObject private var sync = SyncSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var isSyncing: Bool = false
    @State private var lastTickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var nowTick: Date = Date()

    var body: some View {
        Form {
            // ── Status banner — always visible, mirrors the iOS sync pill ──
            Section {
                statusBanner
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Toggle(L("Use iCloud sync", "使用 iCloud 同步"),
                       isOn: $sync.cloudKitEnabled)
                    .help(L("Mirrors notes and events through your iCloud account so other devices stay in sync.",
                            "通过 iCloud 镜像笔记和事件,让其他设备保持同步。"))
                if sync.cloudKitEnabled {
                    Text(L("Restart Doris after toggling iCloud for the change to take effect.",
                           "切换 iCloud 后需重启 Doris 才会生效。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("Local only. Notes stay on this Mac.",
                           "仅本地存储,笔记不会离开本机。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("iCloud")
            }

            Section {
                Toggle(L("Auto-sync every 60 seconds", "每 60 秒自动同步"),
                       isOn: $sync.autoSyncEnabled)
                    .help(L("When on, Doris periodically flushes pending writes so iCloud has the latest state. Turn off if you only want manual sync.",
                            "开启后,Doris 会定期刷写改动到 iCloud。关闭则只在手动同步时触发。"))
            } header: {
                Text(L("Auto-sync", "自动同步"))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button {
                            runManualSync()
                        } label: {
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
                }
            } header: {
                Text(L("Manual sync", "手动同步"))
            } footer: {
                Text(L("Sync Now performs a local save plus a CloudKit reachability check (account status + user record fetch). Last-synced only updates when both succeed.",
                       "立即同步会先本地保存,然后真实验证 iCloud 可达性(账号状态 + 拉取用户 record)。两步都成功才会刷新「上次同步」时间。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .onReceive(lastTickTimer) { nowTick = $0 }
    }

    // MARK: - Status banner

    /// Always-visible state strip at the top of the Sync tab. Reads from
    /// the same `SyncSettings.shared` the toolbar pill uses, so the two
    /// surfaces always agree on whether iCloud is green / red / local.
    private var statusBanner: some View {
        let hasError = sync.lastSyncError != nil
        let accent: Color =
            hasError ? .red :
            !sync.cloudKitEnabled ? Color.primary.opacity(0.45) :
            CyberPalette.neonCyan

        return HStack(spacing: 10) {
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
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent.opacity(hasError ? 0.45 : 0.18), lineWidth: 0.7)
        )
        .padding(.vertical, 4)
    }

    private var bannerIcon: String {
        if sync.lastSyncError != nil { return "exclamationmark.icloud.fill" }
        if !sync.cloudKitEnabled     { return "icloud.slash" }
        if sync.lastSyncedAt == nil  { return "icloud" }
        return "checkmark.icloud.fill"
    }

    private var bannerTitle: String {
        if sync.lastSyncError != nil {
            return L("Sync error", "同步失败")
        }
        if !sync.cloudKitEnabled {
            return L("iCloud sync disabled", "未启用 iCloud 同步")
        }
        if sync.lastSyncedAt == nil {
            return L("Not synced yet", "尚未同步")
        }
        return L("In sync with iCloud", "已与 iCloud 同步")
    }

    private var bannerSubtitle: String {
        if let err = sync.lastSyncError {
            return err
        }
        if !sync.cloudKitEnabled {
            return L("Notes stay on this Mac. Toggle iCloud on below to mirror to other devices.",
                     "笔记仅保存在本机。下方开启 iCloud 即可与其他设备同步。")
        }
        if sync.lastSyncedAt == nil {
            return L("Tap Sync Now below to start a sync.",
                     "点击下方「立即同步」开始第一次同步。")
        }
        return lastSyncedLabel
    }

    /// Friendly "Last synced 30s ago" / "Last synced 2 min ago" label.
    /// Recomputes via `nowTick` once a second so the value stays fresh.
    private var lastSyncedLabel: String {
        guard let last = sync.lastSyncedAt else {
            return L("Never synced yet", "尚未同步")
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        _ = nowTick
        return L("Last synced ", "上次同步 ")
            + f.localizedString(for: last, relativeTo: Date())
    }

    private func runManualSync() {
        isSyncing = true
        AppCommands.syncNow()
        // SyncTimer.pokeNow does its own CloudKit roundtrip; result
        // lands in SyncSettings.shared as either lastSyncedAt update
        // or lastSyncError. The spinner is just visual buffering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isSyncing = false
        }
    }
}

// MARK: - Recently Deleted tab

@MainActor
private struct MacRecentlyDeletedTab: View {
    @Environment(\.modelContext) private var ctx

    @Query(
        // Exclude trashed notes so "Delete All" (which soft-deletes
        // archived items by setting `deleted = true`) makes them
        // disappear from this view immediately. Without the
        // `!note.deleted` clause the records linger here because
        // `archived` stays true after soft-delete, and the user sees
        // "nothing happened".
        filter: #Predicate<Note> { note in note.archived && !note.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var archived: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if archived.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(L("No recently deleted notes.", "暂无最近删除的笔记。"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(L("Notes archived on this device or synced from iOS appear here.",
                           "在本机归档或从 iOS 同步过来的笔记会出现在这里。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text(L("\(archived.count) archived note(s)", "已归档 \(archived.count) 条笔记"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Delete All", "全部删除"), role: .destructive) {
                        // SOFT delete, not ctx.delete — see SchemaV1/Note.swift
                        // notes on the two-flag scheme. Hard-deleting via
                        // `ctx.delete` here races against the other
                        // device's CloudKit mirror: if iOS still has these
                        // notes locally and does a sync poke before our
                        // tombstone propagates, its "still-alive" copy
                        // resurrects the records on the cloud and they
                        // re-appear on every device. Setting deleted=true
                        // + touch is a regular CloudKit update — every
                        // device sees "this is now in trash" with a
                        // monotonic updatedAt. `SyncTimer.purgeTombstones`
                        // will hard-delete after 30 days once we know all
                        // devices have caught up.
                        let now = Date()
                        for n in archived {
                            n.deleted = true
                            n.deletedAt = now
                            n.updatedAt = now
                        }
                        try? ctx.save()
                    }
                    .foregroundStyle(.red)
                }
                List {
                    ForEach(archived) { note in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title.isEmpty ? L("Untitled", "无标题") : note.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(note.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("Restore", "还原")) {
                                note.archived = false
                                note.touch()
                                try? ctx.save()
                            }
                            .controlSize(.small)
                            .foregroundStyle(Color.accentColor)
                            Button(L("Delete Forever", "彻底删除")) {
                                // Same soft-delete reasoning as Delete All
                                // above. Single-note hard delete used to
                                // race CloudKit mirror sync too, just less
                                // visibly because one note re-appearing
                                // looked like "I forgot to click delete".
                                let now = Date()
                                note.deleted = true
                                note.deletedAt = now
                                note.updatedAt = now
                                try? ctx.save()
                            }
                            .controlSize(.small)
                            .foregroundStyle(.red)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(8)
    }
}

// MARK: - SettingsWindowOpacityFix

/// SwiftUI's `Settings` scene hosts content in an NSWindow with
/// `NSVisualEffectView`-backed vibrancy. That's why the previous Settings
/// surface looked semi-transparent regardless of theme — the desktop
/// wallpaper bled through. This NSViewRepresentable reaches up the view
/// hierarchy on first attach, finds the host NSWindow, and:
///
///   · `isOpaque = true`           — stop drawing the window with alpha
///   · `backgroundColor = .clear`  — but let SwiftUI's own backdrop paint
///   · removes any vibrancy view   — kills the blur material so the
///                                   adaptive cyber gradient behind us
///                                   shows through cleanly
///
/// Same TrackingView trick we use for the main window's
/// `WindowConfigurator` to handle the case where SwiftUI calls
/// `makeNSView` before the view is attached to its window.
private struct SettingsWindowOpacityFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = TrackingView()
        v.onMoveToWindow = { configure($0) }
        DispatchQueue.main.async { configure(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = true
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = false

        // Remove any NSVisualEffectView SwiftUI inserted as the window's
        // backing material — the cyber backdrop in `SettingsView.body`
        // already covers the whole content area, so the vibrancy is
        // both invisible and the source of the wash-out.
        if let contentView = window.contentView {
            stripVisualEffects(from: contentView)
        }
    }

    private func stripVisualEffects(from view: NSView) {
        for sub in view.subviews {
            if let vfx = sub as? NSVisualEffectView {
                vfx.isHidden = true
            } else {
                stripVisualEffects(from: sub)
            }
        }
    }

    private final class TrackingView: NSView {
        var onMoveToWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onMoveToWindow?(window)
        }
    }
}
