import Foundation
import SwiftData
import DorisIPC

/// Agent access settings, shared with the Settings UI through UserDefaults
/// so DorisCore doesn't depend on it.
public enum AgentSettings {
    /// Whether agents may change tasks, or only read them. On by default.
    public static let allowWritesKey = "doris.agent.allowWrites"
    /// Whether registering an agent also writes a short "use Doris for
    /// to-dos" note into its CLAUDE.md / AGENTS.md. Off by default.
    public static let writeHintsKey = "doris.agent.writeHints"

    public static var allowWrites: Bool {
        UserDefaults.standard.object(forKey: allowWritesKey) as? Bool ?? true
    }

    public static var writeHints: Bool {
        UserDefaults.standard.object(forKey: writeHintsKey) as? Bool ?? false
    }
}

/// Something an agent changed — for the banner, and for the app's own
/// follow-ups (due-date reminders).
public struct AgentChange: Sendable, Equatable {
    public enum Kind: Sendable { case created, updated, completed, reopened, archived }
    public let kind: Kind
    public let noteID: UUID
    public let title: String
    public let dueDate: Date?
    public let done: Bool
}

public struct AgentToolOutcome {
    public var result: IPCAgentResult
    public var changes: [AgentChange] = []

    static func error(_ text: String) -> AgentToolOutcome {
        AgentToolOutcome(result: IPCAgentResult(text: text, isError: true))
    }
}

/// Carries out agents' tool calls (see `AgentTool`) against the store.
///
/// Every answer is compact JSON that starts from today's date in the
/// user's time zone — agents often don't know it, and need it for "today"
/// and "tomorrow". Errors say how to fix the call, not just that it failed.
/// Nothing here deletes: the strongest thing an agent can do is archive,
/// which the user can undo.
@MainActor
public final class AgentToolRunner {
    private let context: ModelContext
    private let allowWrites: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar

    /// Within this window, creating a task whose title matches a task just
    /// created returns that task instead — a client retrying a call it
    /// thought had failed shouldn't leave duplicates.
    static let duplicateWindow: TimeInterval = 10 * 60

    public init(context: ModelContext,
                allowWrites: @escaping () -> Bool = { AgentSettings.allowWrites },
                clock: @escaping () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.context = context
        self.allowWrites = allowWrites
        self.clock = clock
        self.calendar = calendar
    }

    public func run(tool name: String, arguments json: String) -> AgentToolOutcome {
        guard let tool = AgentTool(rawValue: name) else {
            let names = AgentTool.allCases.map(\.rawValue).joined(separator: ", ")
            return .error("Unknown tool \"\(name)\". Doris has: \(names).")
        }
        if tool.writes && !allowWrites() {
            return .error("Doris is set to let agents read tasks but not change them. "
                + "The user can allow changes in Doris → Settings → Agents (MCP).")
        }
        do {
            let args = try Args(json)
            let now = clock()
            switch tool {
            case .listTasks: return try listTasks(args, now: now)
            case .getTask: return try getTask(args, now: now)
            case .createTask: return try createTask(args, now: now)
            case .updateTask: return try updateTask(args, now: now)
            case .checkItem: return try checkItem(args, now: now)
            case .completeTask: return try completeTask(args, now: now)
            case .archiveTask: return try archiveTask(args, now: now)
            }
        } catch let error as AgentToolError {
            return .error(error.message)
        } catch {
            return .error("Doris couldn't do that: \(error.localizedDescription)")
        }
    }

    // MARK: - Tools

    private func listTasks(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let view = try args.string("view")?.lowercased() ?? "open"
        let views = ["today", "upcoming", "open", "done", "all"]
        guard views.contains(view) else {
            throw AgentToolError("`view` must be one of \(views.joined(separator: ", ")) (got \"\(view)\").")
        }
        let limit = min(max(try args.int("limit") ?? 30, 1), 100)
        let query = try args.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var notes = try liveNotes()
        switch view {
        case "today":
            notes = notes.filter { !$0.isCompleted && ($0.isOverdue(now: now, calendar: calendar)
                || $0.isDueToday(now: now, calendar: calendar) || ($0.pinned && !$0.longTerm)) }
            notes.sort { todayRank($0, now) < todayRank($1, now) }
        case "upcoming":
            notes = notes.filter { !$0.isCompleted && $0.isDueAfterToday(now: now, calendar: calendar) }
            notes.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case "done":
            notes = notes.filter(\.isCompleted)
            notes.sort { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        case "open":
            notes = notes.filter { !$0.isCompleted }
            notes.sort(by: openOrder)
        default:
            notes.sort(by: openOrder)
        }
        if !query.isEmpty {
            // Every word must appear somewhere — "健身房 深蹲" finds the gym
            // task whose title has one word and an item the other.
            let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
            notes = notes.filter { note in
                let haystack = ([note.title, AgentTaskBody.notes(in: note.bodyMarkdown)]
                    + AgentTaskBody.items(in: note.bodyMarkdown).map(\.text)).joined(separator: "\n")
                return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
            }
        }
        var out: [String: Any] = [
            "today": todayLine(now),
            "view": view,
            "total": notes.count,
            "tasks": notes.prefix(limit).map { summary($0, now: now) },
        ]
        if !query.isEmpty { out["query"] = query }
        if notes.count > limit {
            out["more"] = "\(notes.count - limit) more not shown — narrow with `query` or raise `limit`."
        }
        return reply(out)
    }

    private func getTask(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let note = try findNote(try args.requiredString("id"))
        return reply(["today": todayLine(now), "task": full(note, now: now)])
    }

    private func createTask(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let title = try args.requiredString("title").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 300 else { throw AgentToolError("`title` is too long — keep it under 300 characters and put detail in `notes`.") }
        let notesText = try args.string("notes")
        let items = (try args.strings("items") ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard items.count <= 100 else { throw AgentToolError("At most 100 `items` per task.") }
        let due = try args.string("due").flatMap { try parseDue($0, now: now, allowNone: false) }
        let pinned = try args.bool("pinned") ?? false

        // A retry of a call that actually went through.
        let key = title.lowercased()
        if let recent = try liveNotes().first(where: {
            !$0.isCompleted && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
                && now.timeIntervalSince($0.createdAt) < Self.duplicateWindow
        }) {
            return reply([
                "today": todayLine(now),
                "task": full(recent, now: now),
                "note": "A task with this title was created moments ago, so Doris returned it instead of adding a duplicate. Use update_task to change it.",
            ])
        }

        let note = Note(title: title,
                        bodyMarkdown: AgentTaskBody.compose(notes: notesText, items: items),
                        isChecklist: !items.isEmpty,
                        pinned: pinned,
                        dueDate: due)
        context.insert(note)
        try context.save()
        var outcome = reply(["today": todayLine(now), "created": full(note, now: now)])
        outcome.changes = [change(.created, note)]
        return outcome
    }

    private func updateTask(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let note = try findNote(try args.requiredString("id"))
        var touched = false

        if let title = try args.string("title")?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !title.isEmpty else { throw AgentToolError("`title` can't be empty.") }
            note.title = title
            touched = true
        }
        if let more = try args.string("append_notes"), !more.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.bodyMarkdown = AgentTaskBody.appending(notes: more, to: note.bodyMarkdown)
            touched = true
        }
        let items = (try args.strings("add_items") ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !items.isEmpty {
            note.bodyMarkdown = AgentTaskBody.appending(items: items, to: note.bodyMarkdown)
            note.isChecklist = true
            // Same rule as the checklist editor: an open step reopens a done task.
            if note.done { note.done = false; note.completedAt = nil }
            touched = true
        }
        if args.has("due") {
            if args.isNull("due") {
                note.dueDate = nil
            } else {
                note.dueDate = try parseDue(try args.requiredString("due"), now: now, allowNone: true)
            }
            touched = true
        }
        if let pinned = try args.bool("pinned") {
            note.pinned = pinned
            note.longTerm = false
            touched = true
        }
        guard touched else {
            throw AgentToolError("Nothing to change — pass at least one of title, append_notes, add_items, due, pinned.")
        }
        note.touch()
        try context.save()
        var outcome = reply(["today": todayLine(now), "updated": full(note, now: now)])
        outcome.changes = [change(.updated, note)]
        return outcome
    }

    private func checkItem(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let note = try findNote(try args.requiredString("id"))
        guard let number = try args.int("item") else { throw AgentToolError("`item` is required: the item's number from get_task.") }
        let done = try args.bool("done") ?? true
        let items = AgentTaskBody.items(in: note.bodyMarkdown)
        guard !items.isEmpty else {
            throw AgentToolError("This task has no checklist items. Add some with update_task's `add_items`.")
        }
        guard let body = AgentTaskBody.setting(item: number, done: done, in: note.bodyMarkdown) else {
            throw AgentToolError("This task has \(items.count) item\(items.count == 1 ? "" : "s"); `item` must be 1–\(items.count) (got \(number)).")
        }
        note.bodyMarkdown = body
        // Same rule as the checklist editor: ticking the last open item
        // completes the task, unticking one reopens it.
        let allDone = AgentTaskBody.items(in: body).allSatisfy(\.done)
        var kind = AgentChange.Kind.updated
        if allDone && !note.done {
            note.done = true
            note.completedAt = now
            kind = .completed
        } else if !allDone && note.done {
            note.done = false
            note.completedAt = nil
        }
        note.touch()
        try context.save()
        var out: [String: Any] = ["today": todayLine(now), "task": full(note, now: now)]
        if kind == .completed { out["note"] = "That was the last open item, so the task is now done." }
        var outcome = reply(out)
        outcome.changes = [change(kind, note)]
        return outcome
    }

    private func completeTask(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let note = try findNote(try args.requiredString("id"))
        let done = try args.bool("done") ?? true
        note.done = done
        note.completedAt = done ? now : nil
        note.touch()
        try context.save()
        var out: [String: Any] = ["today": todayLine(now), "task": full(note, now: now)]
        if !done, note.isCompleted {
            out["note"] = "All of its checklist items are still ticked, so Doris still shows it as done. Untick one with check_item."
        }
        var outcome = reply(out)
        outcome.changes = [change(done ? .completed : .reopened, note)]
        return outcome
    }

    private func archiveTask(_ args: Args, now: Date) throws -> AgentToolOutcome {
        let note = try findNote(try args.requiredString("id"))
        note.archived = true
        note.archivedAt = now
        note.touch()
        try context.save()
        var outcome = reply([
            "today": todayLine(now),
            "archived": summary(note, now: now),
            "note": "Archived, not deleted: the user can restore it in Doris (Settings → Archived).",
        ])
        outcome.changes = [change(.archived, note)]
        return outcome
    }

    // MARK: - Lookup

    /// Notes on the user's lists: not trashed, not archived.
    private func liveNotes() throws -> [Note] {
        try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { !$0.deleted && !$0.archived }))
    }

    /// By full id, or by a unique prefix of at least 6 characters.
    private func findNote(_ raw: String) throws -> Note {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: text) {
            var fd = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id && !$0.deleted })
            fd.fetchLimit = 1
            if let note = try context.fetch(fd).first { return note }
        } else if text.count >= 6 {
            let prefix = text.lowercased()
            let all = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { !$0.deleted }))
            let matches = all.filter { $0.id.uuidString.lowercased().hasPrefix(prefix) }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { throw AgentToolError("More than one task starts with \"\(text)\"; pass the full id.") }
        }
        throw AgentToolError("No task with id \"\(text)\". Use list_tasks to find its id.")
    }

    // MARK: - Output

    private func summary(_ note: Note, now: Date) -> [String: Any] {
        var d: [String: Any] = ["id": note.id.uuidString, "title": note.title]
        if let due = note.dueDate {
            d["due"] = dayString(due)
            if note.isOverdue(now: now, calendar: calendar) { d["overdue"] = true }
            else if note.isDueToday(now: now, calendar: calendar) && !note.isCompleted { d["due_today"] = true }
        }
        if note.pinned { d[note.longTerm ? "long_term" : "pinned"] = true }
        if note.isCompleted { d["done"] = true }
        let items = AgentTaskBody.items(in: note.bodyMarkdown)
        if !items.isEmpty { d["checklist"] = "\(items.filter(\.done).count)/\(items.count)" }
        return d
    }

    private func full(_ note: Note, now: Date) -> [String: Any] {
        var d = summary(note, now: now)
        let notes = AgentTaskBody.notes(in: note.bodyMarkdown)
        if !notes.isEmpty { d["notes"] = notes }
        let items = AgentTaskBody.items(in: note.bodyMarkdown)
        if !items.isEmpty {
            d["items"] = items.map { ["n": $0.number, "done": $0.done, "text": $0.text] as [String: Any] }
        }
        d["created"] = timeString(note.createdAt)
        d["updated"] = timeString(note.updatedAt)
        if let c = note.completedAt, note.done { d["completed"] = timeString(c) }
        if note.archived { d["archived"] = true }
        return d
    }

    private func reply(_ object: [String: Any]) -> AgentToolOutcome {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return AgentToolOutcome(result: IPCAgentResult(text: String(decoding: data, as: UTF8.self)))
    }

    private func change(_ kind: AgentChange.Kind, _ note: Note) -> AgentChange {
        AgentChange(kind: kind, noteID: note.id, title: note.title, dueDate: note.dueDate, done: note.isCompleted)
    }

    // MARK: - Ordering

    /// Today's list: overdue first (oldest first), then due today, then pinned.
    private func todayRank(_ note: Note, _ now: Date) -> (Int, Date, Double) {
        if note.isOverdue(now: now, calendar: calendar) { return (0, note.dueDate ?? now, 0) }
        if note.isDueToday(now: now, calendar: calendar) { return (1, note.dueDate ?? now, 0) }
        return (2, .distantFuture, note.order)
    }

    /// Dated tasks by date, then pinned, then most recently changed.
    private func openOrder(_ a: Note, _ b: Note) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if a.pinned != b.pinned { return a.pinned }
        return a.updatedAt > b.updatedAt
    }

    // MARK: - Dates

    private func parseDue(_ raw: String, now: Date, allowNone: Bool) throws -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let today = calendar.startOfDay(for: now)
        switch text {
        case "today": return today
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: today)
        case "none", "":
            if allowNone { return nil }
        default:
            // YYYY-MM-DD, also taken from the front of a full timestamp.
            let day = String(text.prefix(10))
            let parts = day.split(separator: "-").compactMap { Int($0) }
            if day.count == 10, parts.count == 3,
               let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
               calendar.component(.day, from: date) == parts[2] {
                return calendar.startOfDay(for: date)
            }
        }
        throw AgentToolError("`due` must be YYYY-MM-DD, today or tomorrow\(allowNone ? ", or none to clear it" : "") (got \"\(raw)\").")
    }

    private func todayLine(_ now: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd (EEEE)"
        return "\(f.string(from: now)) \(calendar.timeZone.identifier)"
    }

    private func dayString(_ date: Date) -> String { format(date, "yyyy-MM-dd") }
    private func timeString(_ date: Date) -> String { format(date, "yyyy-MM-dd HH:mm") }

    private func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

struct AgentToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// A tool call's arguments, with type checks that explain themselves.
/// Lenient where it's harmless: "true" for true, "3" for 3, a single
/// string where a list is expected.
struct Args {
    private let values: [String: Any]

    init(_ json: String) throws {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { values = [:]; return }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let dict = object as? [String: Any] else {
            throw AgentToolError("Arguments must be a JSON object.")
        }
        values = dict
    }

    func has(_ key: String) -> Bool { values[key] != nil }
    func isNull(_ key: String) -> Bool { values[key] is NSNull }

    func string(_ key: String) throws -> String? {
        guard let v = values[key], !(v is NSNull) else { return nil }
        if let s = v as? String { return s }
        throw AgentToolError("`\(key)` must be a string.")
    }

    func requiredString(_ key: String) throws -> String {
        guard let s = try string(key), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError("`\(key)` is required.")
        }
        return s
    }

    func bool(_ key: String) throws -> Bool? {
        guard let v = values[key], !(v is NSNull) else { return nil }
        if let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        if let s = v as? String {
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: break
            }
        }
        throw AgentToolError("`\(key)` must be true or false.")
    }

    func int(_ key: String) throws -> Int? {
        guard let v = values[key], !(v is NSNull) else { return nil }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
        if let s = v as? String, let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
        throw AgentToolError("`\(key)` must be a number.")
    }

    func strings(_ key: String) throws -> [String]? {
        guard let v = values[key], !(v is NSNull) else { return nil }
        if let a = v as? [Any] {
            return try a.map {
                guard let s = $0 as? String else { throw AgentToolError("`\(key)` must be a list of strings.") }
                return s
            }
        }
        if let s = v as? String { return [s] }
        throw AgentToolError("`\(key)` must be a list of strings.")
    }
}
