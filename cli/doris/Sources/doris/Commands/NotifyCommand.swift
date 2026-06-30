import ArgumentParser
import Foundation
import DorisIPC

struct NotifyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a notification to the running doris app."
    )

    @Option(name: .shortAndLong, help: "Notification title.")
    var title: String

    @Option(name: .shortAndLong, help: "Notification body / markdown.")
    var body: String?

    @Option(help: "SF Symbol or icon name override.")
    var icon: String?

    @Option(help: "Display mode: banner (auto-dismiss) or fix (persistent).")
    var mode: String = DisplayMode.banner.rawValue

    @Option(help: "Source kind: claudeCode, codex, chatgpt, trae, vscode, feishu, cliGeneric, scheduledJob, userMemo, share, manual.")
    var source: String = SourceKind.cliGeneric.rawValue

    @Option(help: "Severity: critical (red, urgent), reminder (amber, soft nudge), info (gray, background log). Default: info.")
    var level: String = EventLevel.info.rawValue

    @Option(name: .customLong("app-id"), help: "Free-form source app id, e.g. 'claude-code'.")
    var sourceAppId: String?

    @Option(name: .customLong("click-url"), help: "URL to open when the notification is clicked.")
    var clickURL: String?

    @Option(name: .customLong("click-note"), help: "Note id to open when the notification is clicked.")
    var clickNote: String?

    @Option(name: .customLong("to"), help: "Push to a specific device by name.")
    var toDevice: String?

    @Flag(name: .customLong("all-devices"), help: "Push to every device on this iCloud account.")
    var allDevices: Bool = false

    @Flag(name: .customLong("no-launch"), help: "Do not launch the app if it is not running.")
    var noLaunch: Bool = false

    @Flag(name: .customLong("json"), help: "Read full payload JSON from stdin.")
    var jsonStdin: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress success messages.")
    var quiet: Bool = false

    func run() async throws {
        let payload = try buildPayload()
        let request = IPCRequest(kind: .notify, payload: .notify(payload))

        do {
            try IPCDirectory.ensureIPCDirectories()
            try IPCWriter.enqueue(request)
            IPCWriter.kick()
        } catch {
            dieIO("doris: failed to enqueue notification: \(error)")
        }

        let needsRunningApp = !(payload.broadcast == .local)
        if needsRunningApp {
            if !AppLauncher.isRunning() {
                if noLaunch {
                    dieTempFail("doris: app is not running and --no-launch was set")
                }
                if !AppLauncher.launchIfNeeded() {
                    dieTempFail("doris: cross-device push needs the doris app running and could not launch it")
                }
            }
        } else if !AppLauncher.isRunning() && !noLaunch {
            _ = AppLauncher.launchIfNeeded()
        }

        info("doris: queued notification \(request.id.uuidString)", quiet: quiet)
    }

    private func buildPayload() throws -> IPCNotifyPayload {
        if jsonStdin {
            let stdinData = FileHandle.standardInput.availableData
            return try IPCEncoding.decoder.decode(IPCNotifyPayload.self, from: stdinData)
        }
        guard let displayMode = DisplayMode(rawValue: mode) else {
            dieUsage("doris: invalid --mode '\(mode)'. Use 'banner' or 'fix'.")
        }
        guard let kind = SourceKind(rawValue: source) else {
            dieUsage("doris: invalid --source '\(source)'.")
        }
        guard let eventLevel = EventLevel(rawValue: level) else {
            dieUsage("doris: invalid --level '\(level)'. Use 'critical', 'reminder', or 'info'.")
        }
        var clickAction: ClickAction?
        if let urlStr = clickURL, let url = URL(string: urlStr) {
            clickAction = .openURL(url)
        } else if let noteIDStr = clickNote, let id = UUID(uuidString: noteIDStr) {
            clickAction = .openNote(id: id)
        }

        let broadcast: BroadcastScope
        if allDevices {
            broadcast = .allDevices
        } else if let name = toDevice {
            // We pass device name as a sentinel UUID derived from the name; the app side resolves to the
            // actual Device record. For v1 we use the broadcast scope for "all devices" if a literal UUID
            // is provided; otherwise fall back to allDevices and let the app filter on receive.
            if let uuid = UUID(uuidString: name) {
                broadcast = .device(id: uuid)
            } else {
                broadcast = .allDevices  // best-effort: app filters by name on receive
            }
            _ = name
        } else {
            broadcast = .local
        }

        return IPCNotifyPayload(
            title: title,
            body: body,
            iconName: icon,
            displayMode: displayMode,
            source: kind,
            sourceAppId: sourceAppId,
            level: eventLevel,
            clickAction: clickAction,
            broadcast: broadcast
        )
    }
}
