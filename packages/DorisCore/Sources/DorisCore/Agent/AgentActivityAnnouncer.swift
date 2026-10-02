import Foundation
import DorisIPC

/// Who is calling, from the MCP client's self-reported name.
public struct AgentClient: Sendable, Equatable {
    public let rawName: String

    public init(_ rawName: String) { self.rawName = rawName }

    public var displayName: String {
        let n = rawName.lowercased()
        if n.contains("claude-code") || n.contains("claude code") { return "Claude Code" }
        if n.contains("codex") { return "Codex" }
        if n.contains("claude") { return "Claude" }
        if n.contains("cursor") { return "Cursor" }
        if n.contains("lm studio") || n.contains("lmstudio") { return "LM Studio" }
        return rawName.isEmpty ? "Agent" : rawName
    }

    /// Drives the banner's icon: Claude and Codex have their own marks.
    public var source: SourceKind {
        let n = rawName.lowercased()
        if n.contains("codex") { return .codex }
        if n.contains("claude") { return .claudeCode }
        return .cliGeneric
    }
}

/// Tells the user, in the notch, what an agent just did to their tasks.
///
/// Agents tend to work in bursts — five tasks from one request, a run of
/// ticks — so changes are gathered for a moment and shown as one banner
/// per agent: "Claude Code added “…”" for a single change, "Claude Code
/// changed 4 tasks" for several. Clicking a single-task banner opens it.
@MainActor
public final class AgentActivityAnnouncer {
    private let present: (PresentableMessage) -> Void
    private let settle: Duration
    private var pending: [String: (client: AgentClient, changes: [AgentChange])] = [:]
    private var flushTask: Task<Void, Never>?

    public init(settle: Duration = .milliseconds(1500), present: @escaping (PresentableMessage) -> Void) {
        self.settle = settle
        self.present = present
    }

    public func record(_ changes: [AgentChange], by client: AgentClient) {
        guard !changes.isEmpty else { return }
        pending[client.rawName, default: (client, [])].changes += changes
        flushTask?.cancel()
        flushTask = Task { [weak self, settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        let batches = pending.values
        pending = [:]
        for batch in batches {
            present(Self.message(for: batch.changes, by: batch.client))
        }
    }

    nonisolated static func message(for changes: [AgentChange], by client: AgentClient,
                                    zh: Bool = AgentActivityAnnouncer.prefersChinese) -> PresentableMessage {
        let who = client.displayName
        // The same task touched several times in a row is one change to the user.
        var byNote: [UUID: AgentChange] = [:]
        var order: [UUID] = []
        for c in changes {
            if byNote[c.noteID] == nil { order.append(c.noteID) }
            // Keep the most telling kind: created beats a follow-up update.
            if let prior = byNote[c.noteID], prior.kind == .created, c.kind == .updated {
                byNote[c.noteID] = AgentChange(kind: .created, noteID: c.noteID, title: c.title, dueDate: c.dueDate, done: c.done)
            } else {
                byNote[c.noteID] = c
            }
        }
        let distinct = order.compactMap { byNote[$0] }

        let title: String
        var body: String?
        var click: ClickAction?
        if distinct.count == 1, let c = distinct.first {
            let name = c.title.isEmpty ? (zh ? "一个任务" : "a task") : (zh ? "「\(c.title)」" : "“\(c.title)”")
            title = zh ? "\(who) \(verbZH(c.kind))了\(name)" : "\(who) \(verbEN(c.kind)) \(name)"
            click = .openNote(id: c.noteID)
        } else {
            let kinds = Set(distinct.map(\.kind))
            if kinds.count == 1, let k = kinds.first {
                title = zh ? "\(who) \(verbZH(k))了 \(distinct.count) 个任务" : "\(who) \(verbEN(k)) \(distinct.count) tasks"
            } else {
                title = zh ? "\(who) 改动了 \(distinct.count) 个任务" : "\(who) changed \(distinct.count) tasks"
            }
            let names = distinct.prefix(3).map(\.title).filter { !$0.isEmpty }
            body = names.joined(separator: zh ? "、" : ", ") + (distinct.count > 3 ? "…" : "")
        }
        return PresentableMessage(
            id: UUID(), title: title, body: body,
            source: client.source, sourceAppId: client.rawName, iconName: nil,
            level: .info, displayMode: .banner, receivedAt: Date(), clickAction: click)
    }

    private nonisolated static func verbZH(_ k: AgentChange.Kind) -> String {
        switch k {
        case .created: return "新建"
        case .updated: return "更新"
        case .completed: return "完成"
        case .reopened: return "重开"
        case .archived: return "归档"
        }
    }

    private nonisolated static func verbEN(_ k: AgentChange.Kind) -> String {
        switch k {
        case .created: return "added"
        case .updated: return "updated"
        case .completed: return "completed"
        case .reopened: return "reopened"
        case .archived: return "archived"
        }
    }

    /// The app's language setting, read where DorisUI's LanguageSettings
    /// writes it so DorisCore stays UI-independent.
    nonisolated static var prefersChinese: Bool {
        (UserDefaults.standard.string(forKey: "doris.language.mode") ?? "zh") != "en"
    }
}
