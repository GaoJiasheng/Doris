import SwiftUI
import DorisUI

struct DorisCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("New Task", "新建任务")) {
                if let url = URL(string: "doris://new-note") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("n")
        }
        CommandGroup(after: .appInfo) {
            Button(L("Sync Now", "立即同步")) {
                if let url = URL(string: "doris://sync") {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}
