import SwiftUI
import DorisCore
#if os(macOS)
import AppKit
#endif

/// Compact sync-status pill used in the macOS main window's detail header.
/// Always-visible state + click-to-act:
///   · Normal (cloud OK)     → cyan `↻ 2 min ago`           ; click = Sync Now
///   · Local-only (cloud off)→ muted `☁︎ 未启用 iCloud`        ; click = popover (with Open Settings)
///   · Error                 → red `⚠ <truncated reason>`   ; click = popover (full error + Retry + Open Settings)
///   · Tap pending           → spinner + `同步中…`           ; (disabled)
///
/// Hover also shows the same content via macOS's standard `.help()`
/// tooltip, but a single click is the discoverable path: rather than
/// silently retry a sync the user can't see, the click opens a small
/// popover anchored to the pill with the full state + actionable
/// buttons (Retry, Open Sync Settings).
public struct SyncNowToolbarButton: View {
    @ObservedObject private var sync = SyncSettings.shared
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var spinning: Bool = false
    @State private var nowTick: Date = Date()
    @State private var showDetails: Bool = false
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// When false, render just the status icon (no "X ago" relative time) —
    /// used in the main-window toolbar where the time was redundant clutter.
    private let showsTime: Bool

    public init(showsTime: Bool = true) { self.showsTime = showsTime }

    public var body: some View {
        Button { handleTap() } label: { pillBody }
        .buttonStyle(.plain)
        .disabled(spinning)
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            detailsPopover
        }
        // Only tick the relative-time label when it's actually shown.
        .onReceive(tickTimer) { if showsTime { nowTick = $0 } }
    }

    // MARK: - Pill body

    private var pillBody: some View {
        HStack(spacing: 5) {
            leadingIcon
            if showsTime {
                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, showsTime ? 8 : 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(.primary.opacity(0.05)))
        .overlay(Capsule().stroke(strokeColor, lineWidth: 0.6))
        .help(helpText)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if spinning {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.75)
                .tint(accentColor)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Tap routing

    /// Click semantics differ by state:
    ///   · Normal: silently fire a sync (low-friction repeat action)
    ///   · Local-only or Error: open the details popover so the user
    ///     gets context and explicit Retry / Open Settings actions.
    private func handleTap() {
        if hasError || !sync.cloudKitEnabled {
            showDetails = true
        } else {
            performSync()
        }
    }

    private func performSync() {
        spinning = true
        AppCommands.syncNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            spinning = false
        }
    }

    // MARK: - Details popover

    private var detailsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header — icon + title + subtitle
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: detailIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(detailTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hasError ? .red : .primary)
                    Text(detailBody)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    showDetails = false
                    openSyncSettings()
                } label: {
                    Label(L("Open Sync Settings", "打开同步设置"),
                          systemImage: "gearshape")
                }
                Spacer()
                if sync.cloudKitEnabled {
                    Button {
                        showDetails = false
                        performSync()
                    } label: {
                        Label(L("Retry", "重试"),
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Route through `AppCommands.openSettings` so the host app gets to
    /// decide which Settings UI to open. On Mac this lands on the
    /// stand-alone `SettingsWindowController` panel (same one the
    /// menu-bar avatar's right-click → "Settings…" opens), keeping a
    /// single mental model of "the Settings window".
    private func openSyncSettings() {
        AppCommands.openSettings()
    }

    // MARK: - Derived visuals

    private var hasError: Bool { sync.lastSyncError != nil }

    private var iconName: String {
        if hasError { return "exclamationmark.icloud.fill" }
        if !sync.cloudKitEnabled { return "icloud.slash" }
        return "arrow.triangle.2.circlepath"
    }

    private var accentColor: Color {
        if hasError { return .red }
        if !sync.cloudKitEnabled { return Color.primary.opacity(0.45) }
        return CyberPalette.neonCyan
    }

    private var strokeColor: Color {
        if hasError { return Color.red.opacity(0.55) }
        if !sync.cloudKitEnabled { return Color.primary.opacity(0.18) }
        return CyberPalette.neonCyan.opacity(0.35)
    }

    private var textColor: Color {
        if hasError { return .red }
        if !sync.cloudKitEnabled { return Color.primary.opacity(0.5) }
        return Color.primary.opacity(0.65)
    }

    private var statusLabel: String {
        if spinning { return L("Syncing…", "同步中…") }
        if let err = sync.lastSyncError { return truncate(err, max: 18) }
        if !sync.cloudKitEnabled { return L("iCloud off", "未启用 iCloud") }
        guard let last = sync.lastSyncedAt else {
            return L("Never synced", "尚未同步")
        }
        _ = nowTick
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: last, relativeTo: Date())
    }

    private var helpText: String {
        if let err = sync.lastSyncError {
            return L("Sync error: \(err)\nClick for details.",
                     "同步错误:\(err)\n点击查看详情。")
        }
        if !sync.cloudKitEnabled {
            return L("iCloud sync is off. Click to enable.",
                     "iCloud 同步未启用。点击查看详情。")
        }
        var label = L("Sync Now", "立即同步")
        if let last = sync.lastSyncedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            label += "\n" + L("Last synced ", "上次同步 ")
                + f.localizedString(for: last, relativeTo: Date())
        } else {
            label += "\n" + L("Never synced", "尚未同步")
        }
        return label
    }

    // MARK: - Popover content (errors / local-only)

    private var detailIcon: String {
        if hasError { return "exclamationmark.triangle.fill" }
        if !sync.cloudKitEnabled { return "icloud.slash" }
        return "checkmark.icloud.fill"
    }

    private var detailTitle: String {
        if hasError {
            return L("Sync failed", "同步失败")
        }
        if !sync.cloudKitEnabled {
            return L("iCloud sync is off", "iCloud 同步未启用")
        }
        return L("In sync", "已同步")
    }

    private var detailBody: String {
        if let err = sync.lastSyncError {
            return err
        }
        if !sync.cloudKitEnabled {
            return L(
                "Notes only live on this Mac. Open Sync Settings and enable \"Use iCloud sync\" to mirror your data across devices.",
                "笔记仅保存在本机。打开「同步设置」并启用「使用 iCloud 同步」即可在多设备之间镜像数据。"
            )
        }
        if let last = sync.lastSyncedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return L("Last synced ", "上次同步 ")
                + f.localizedString(for: last, relativeTo: Date())
        }
        return L("Never synced yet", "尚未同步")
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max)) + "…"
    }
}
