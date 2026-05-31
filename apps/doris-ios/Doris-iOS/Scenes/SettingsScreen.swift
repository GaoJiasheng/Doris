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
                recentlyDeletedSection
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

    /// Recently Deleted — shows archived notes so the user can restore or
    /// permanently delete them. SyncTimer auto-purges after 30 days.
    private var recentlyDeletedSection: some View {
        IOSRecentlyDeletedSection()
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text(L("Version", "版本"))
                    .foregroundStyle(.primary)
                Spacer()
                Text("0.7.0")
                    .foregroundStyle(.primary.opacity(0.6))
                    .monospacedDigit()
            }
        } header: {
            Text(L("About", "关于"))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .listRowBackground(Color.primary.opacity(0.05))
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

/// Recently Deleted section — lists archived notes with Restore + hard-delete.
/// Isolated struct so its @Query doesn't churn the parent Settings body.
private struct IOSRecentlyDeletedSection: View {
    @Environment(\.modelContext) private var ctx

    @Query(
        // Excludes notes that have been soft-deleted (`deleted = true`)
        // because "Delete All" / per-row delete moves them to that
        // state — see SyncTimer.purgeTombstones for the rationale
        // (avoiding CloudKit-mirror resurrection race).
        filter: #Predicate<Note> { note in note.archived && !note.deleted },
        sort: [SortDescriptor(\Note.updatedAt, order: .reverse)]
    )
    private var archived: [Note]

    var body: some View {
        Section {
            if archived.isEmpty {
                Text(L("No recently deleted notes.", "没有最近删除的笔记。"))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.5))
            } else {
                ForEach(archived) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty
                                 ? L("Untitled", "无标题")
                                 : note.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(note.updatedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                        Spacer()
                        Button(L("Restore", "恢复")) {
                            note.archived = false
                            note.touch()
                            try? ctx.save()
                        }
                        .font(.caption)
                        .foregroundStyle(CyberPalette.neonCyan)
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            // Soft-delete; SyncTimer.purgeTombstones
                            // hard-deletes 24h after deletedAt once the
                            // flag has propagated to every device.
                            let now = Date()
                            note.deleted = true
                            note.deletedAt = now
                            note.updatedAt = now
                            try? ctx.save()
                        } label: {
                            Label(L("Delete Forever", "永久删除"), systemImage: "trash")
                        }
                    }
                }
                Button(role: .destructive) {
                    let now = Date()
                    for note in archived {
                        note.deleted = true
                        note.deletedAt = now
                        note.updatedAt = now
                    }
                    try? ctx.save()
                } label: {
                    Text(L("Delete All (\(archived.count))",
                           "全部删除 (\(archived.count))"))
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text(L("Recently Deleted", "最近删除"))
                .foregroundStyle(.primary.opacity(0.7))
        } footer: {
            Text(L("Notes are permanently deleted after 30 days.",
                   "笔记将在 30 天后自动永久删除。"))
                .foregroundStyle(.primary.opacity(0.5))
        }
        .listRowBackground(Color.primary.opacity(0.05))
    }
}
