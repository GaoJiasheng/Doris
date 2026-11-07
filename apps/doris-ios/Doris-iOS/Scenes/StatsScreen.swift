import SwiftUI
import DorisCore
import DorisUI

/// Read-only view of the activity your Macs record — tokens, meeting time
/// and typing, summed across Macs. The iPhone records nothing itself.
struct StatsScreen: View {
    @ObservedObject private var lang = LanguageSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ActivityOverview()
                Text(L("Recorded by Doris on your Macs and synced through iCloud.",
                       "由各台 Mac 上的 Doris 记录，经 iCloud 同步。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background { CyberBackground().ignoresSafeArea() }
        .navigationTitle(L("Stats", "统计"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
