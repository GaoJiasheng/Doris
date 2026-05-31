import SwiftUI
import SwiftData
import DorisCore
import DorisUI

/// iOS Settings tab — Theme, Language, Sync, About.
/// Now hosted as a top-level RootTabView tab (was previously a sheet
/// triggered from the NotesScreen toolbar gear button).
struct SettingsScreen: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @ObservedObject private var theme = ThemeSettings.shared
    @ObservedObject private var sync = SyncSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                themeSection
                languageSection
                syncSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background {
                CyberBackground().ignoresSafeArea()
            }
            .navigationTitle(L("Settings", "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var themeSection: some View {
        Section {
            Picker(selection: $theme.mode) {
                ForEach(ThemeSettings.Mode.allCases) { m in
                    Label(m.displayName, systemImage: m.iconName).tag(m)
                }
            } label: {
                Text(L("Theme", "主题"))
                    .foregroundStyle(.primary)
            }
        } header: {
            Text(L("Appearance", "外观"))
                .foregroundStyle(.primary.opacity(0.7))
        } footer: {
            Text(L("Dark uses the deep purple cyber backdrop. Light uses a softer cream version with the same neon accents.",
                   "深色为标准赛博紫黑底,浅色为柔和奶油底,两种模式都保留同样的霓虹粉青配色。"))
                .foregroundStyle(.primary.opacity(0.5))
        }
        .listRowBackground(Color.primary.opacity(0.05))
    }

    private var languageSection: some View {
        Section {
            Picker(selection: $lang.mode) {
                ForEach(LanguageSettings.Mode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            } label: {
                Text(L("Display", "显示"))
                    .foregroundStyle(.primary)
            }
        } header: {
            Text(L("Language", "语言"))
                .foregroundStyle(.primary.opacity(0.7))
        } footer: {
            Text(L("Switch the UI between English, Chinese, or both side-by-side.",
                   "在英文、中文或双语之间切换界面显示。"))
                .foregroundStyle(.primary.opacity(0.5))
        }
        .listRowBackground(Color.primary.opacity(0.05))
    }

    /// Sync section — mirrors the Mac Settings → Sync tab. CloudKit
    /// toggle, auto-sync toggle, manual "Sync Now" with last-synced
    /// timestamp updated live.
    private var syncSection: some View {
        Section {
            Toggle(isOn: $sync.cloudKitEnabled) {
                Text(L("Use iCloud sync", "使用 iCloud 同步"))
                    .foregroundStyle(.primary)
            }
            Toggle(isOn: $sync.autoSyncEnabled) {
                Text(L("Auto-sync every minute", "每分钟自动同步"))
                    .foregroundStyle(.primary)
            }
            IOSSyncNowRow()
        } header: {
            Text(L("Sync", "同步"))
                .foregroundStyle(.primary.opacity(0.7))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if sync.cloudKitEnabled {
                    Text(L("Restart Doris after toggling iCloud for the change to take effect.",
                           "切换 iCloud 后需要重启 Doris 才能生效。"))
                } else {
                    Text(L("Local only. Notes stay on this device.",
                           "仅本地存储,笔记不会离开本机。"))
                }
            }
            .foregroundStyle(.primary.opacity(0.5))
        }
        .listRowBackground(Color.primary.opacity(0.05))
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text(L("Version", "版本"))
                    .foregroundStyle(.primary)
                Spacer()
                Text(Self.appVersionString)
                    .foregroundStyle(.primary.opacity(0.6))
                    .monospacedDigit()
            }
        } header: {
            Text(L("About", "关于"))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .listRowBackground(Color.primary.opacity(0.05))
    }

    /// "1.0.0 (2)" style — reads MARKETING_VERSION and
    /// CURRENT_PROJECT_VERSION via the standard Info.plist keys, so
    /// the Settings row tracks `project.yml` without manual edits.
    /// Earlier we hardcoded "0.7.0" and it drifted three releases out
    /// of date before anyone noticed.
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }
}

/// "Sync Now" row — button + live last-synced timestamp + error display.
private struct IOSSyncNowRow: View {
    @ObservedObject private var sync = SyncSettings.shared
    @State private var isSyncing: Bool = false
    @State private var nowTick: Date = Date()
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    tap()
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(CyberPalette.neonCyan)
                        }
                        Text(isSyncing
                             ? L("Syncing…", "同步中…")
                             : L("Sync Now", "立即同步"))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                Spacer()
                Text(lastSyncedLabel)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.55))
                    .monospacedDigit()
            }
            // Error row — only shown when there's an active sync error
            if let err = sync.lastSyncError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .onReceive(tickTimer) { nowTick = $0 }
    }

    private var lastSyncedLabel: String {
        guard let last = sync.lastSyncedAt else {
            return L("Never synced", "尚未同步")
        }
        _ = nowTick
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: last, relativeTo: Date())
    }

    private func tap() {
        isSyncing = true
        AppCommands.syncNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isSyncing = false
        }
    }
}

// IOSRecentlyDeletedSection removed in 1.0.0 — the section header
// said "Recently Deleted" but the @Query was `note.archived &&
// !note.deleted`, surfacing the *archived* list (which the Notes-tab
// "已归档" sheet already covers via the top-right archivebox icon).
// Two surfaces for the same data confused users about what each one
// actually did. If a real Trash UI for `note.deleted == true` is
// ever wanted, build it as a new section / sheet with the correct
// predicate and header — don't revive this struct.
