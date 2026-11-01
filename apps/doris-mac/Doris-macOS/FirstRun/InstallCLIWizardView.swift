import SwiftUI
import DorisCore
import DorisUI

struct InstallCLIWizardView: View {
    @ObservedObject private var lang = LanguageSettings.shared
    @State private var status: String = ""
    @State private var lastInstalledPath: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Install the `doris` CLI", "安装 `doris` 命令行工具"))
                .font(.title2)
            Text(L(
                "This will symlink the CLI bundled inside Doris.app to /usr/local/bin/doris so you can run `doris notify ...` from any shell.",
                "这会把 Doris.app 内置的 CLI 符号链接到 /usr/local/bin/doris，这样你在任意 shell 里都能跑 `doris notify ...`。"
            ))
                .font(.body)
            // Display status only when non-empty so the wizard doesn't
            // show a stale "Ready" line on first open.
            if !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Install to /usr/local/bin", "安装到 /usr/local/bin")) {
                    install(to: "/usr/local/bin/doris")
                }
                .keyboardShortcut(.defaultAction)
                Button(L("Install to ~/.local/bin", "安装到 ~/.local/bin")) {
                    let home = ProcessInfo.processInfo.environment["HOME"] ?? "~"
                    install(to: "\(home)/.local/bin/doris")
                }
                Button(L("Skip", "跳过")) { onClose() }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func install(to destination: String) {
        guard let bundleCLI = Bundle.main.url(forResource: "doris", withExtension: nil) else {
            status = L("Could not locate the bundled CLI.", "找不到 app 内置的 CLI。")
            return
        }
        let dest = (destination as NSString).standardizingPath
        let parent = (dest as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: parent) {
            do {
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            } catch {
                status = L("Could not create \(parent). You may need to run: sudo mkdir -p \(parent)",
                           "无法创建 \(parent)。可能需要手动运行：sudo mkdir -p \(parent)")
                return
            }
        }
        do {
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.createSymbolicLink(atPath: dest, withDestinationPath: bundleCLI.path)
            status = L("Installed to \(dest)", "已安装到 \(dest)")
            lastInstalledPath = dest
        } catch {
            status = L(
                "Failed: \(error.localizedDescription). You may need to install manually: ln -s \(bundleCLI.path) \(dest)",
                "失败：\(error.localizedDescription)。可手动安装：ln -s \(bundleCLI.path) \(dest)"
            )
        }
    }
}
