import XCTest
import SwiftData
import DorisIPC
@testable import DorisCore

@MainActor
final class AgentToolRunnerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var allowWrites = true
    /// Friday 2 Oct 2026, 15:00 in Singapore.
    private var now = ISO8601DateFormatter().date(from: "2026-10-02T07:00:00Z")!
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return c
    }()

    override func setUp() async throws {
        container = try ModelContainerFactory.make(inMemory: true)
        allowWrites = true
    }

    private var runner: AgentToolRunner {
        AgentToolRunner(context: context, allowWrites: { [unowned self] in allowWrites },
                        clock: { [unowned self] in now }, calendar: calendar)
    }

    @discardableResult
    private func call(_ tool: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self)
        let outcome = runner.run(tool: tool, arguments: json)
        XCTAssertFalse(outcome.result.isError, outcome.result.text)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(outcome.result.text.utf8)) as? [String: Any])
    }

    private func error(_ tool: String, _ args: [String: Any] = [:]) -> String {
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: args), as: UTF8.self)
        let outcome = runner.run(tool: tool, arguments: json)
        XCTAssertTrue(outcome.result.isError, "expected an error from \(tool)")
        return outcome.result.text
    }

    private func day(_ s: String) -> Date {
        let p = s.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }

    // MARK: -

    func testCreateWithItemsMakesOneChecklistTask() throws {
        let out = try call("create_task", ["title": "Review PR #42", "notes": "From Alex", "items": ["Read diff", "Run tests"], "due": "tomorrow"])
        XCTAssertEqual(out["today"] as? String, "2026-10-02 (Friday) Asia/Singapore")
        let task = try XCTUnwrap(out["created"] as? [String: Any])
        XCTAssertEqual(task["due"] as? String, "2026-10-03")
        XCTAssertEqual(task["checklist"] as? String, "0/2")
        XCTAssertEqual(task["notes"] as? String, "From Alex")
        let items = try XCTUnwrap(task["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["n"] as? Int }, [1, 2])

        let note = try XCTUnwrap(try context.fetch(FetchDescriptor<Note>()).first)
        XCTAssertTrue(note.isChecklist)
        XCTAssertEqual(note.bodyMarkdown, "From Alex\n- [ ] Read diff\n- [ ] Run tests")
        XCTAssertEqual(note.dueDate, day("2026-10-03"))
    }

    func testTodayIsOverdueDueTodayAndPinned() throws {
        let overdue = Note(title: "late", dueDate: day("2026-09-30"))
        let dueToday = Note(title: "now", dueDate: day("2026-10-02"))
        let later = Note(title: "later", dueDate: day("2026-10-05"))
        let pinned = Note(title: "pinned", pinned: true)
        let longTerm = Note(title: "forever", pinned: true); longTerm.longTerm = true
        let done = Note(title: "done", dueDate: day("2026-10-02")); done.done = true
        let archived = Note(title: "gone", dueDate: day("2026-10-02")); archived.archived = true
        [overdue, dueToday, later, pinned, longTerm, done, archived].forEach(context.insert)
        try context.save()

        let today = try call("list_tasks", ["view": "today"])
        XCTAssertEqual((today["tasks"] as? [[String: Any]])?.map { $0["title"] as? String }, ["late", "now", "pinned"])
        XCTAssertEqual((today["tasks"] as? [[String: Any]])?.first?["overdue"] as? Bool, true)

        let upcoming = try call("list_tasks", ["view": "upcoming"])
        XCTAssertEqual((upcoming["tasks"] as? [[String: Any]])?.map { $0["title"] as? String }, ["later"])

        let open = try call("list_tasks")
        XCTAssertEqual(open["total"] as? Int, 5)
        let doneList = try call("list_tasks", ["view": "done"])
        XCTAssertEqual((doneList["tasks"] as? [[String: Any]])?.map { $0["title"] as? String }, ["done"])
    }

    func testQueryLimitAndMore() throws {
        for i in 1...5 { context.insert(Note(title: "Email \(i)")) }
        context.insert(Note(title: "Gym"))
        try context.save()
        let out = try call("list_tasks", ["query": "email", "limit": 2])
        XCTAssertEqual(out["total"] as? Int, 5)
        XCTAssertEqual((out["tasks"] as? [Any])?.count, 2)
        XCTAssertNotNil(out["more"])
    }

    func testQueryWordsCanMatchDifferentParts() throws {
        context.insert(Note(title: "健身房:练腿", bodyMarkdown: "- [ ] 深蹲 5×5", isChecklist: true))
        context.insert(Note(title: "深蹲视频"))
        try context.save()
        let out = try call("list_tasks", ["query": "健身房 深蹲"])
        XCTAssertEqual((out["tasks"] as? [[String: Any]])?.map { $0["title"] as? String }, ["健身房:练腿"])
    }

    func testTickingTheLastItemCompletesAndUntickingReopens() throws {
        let created = try call("create_task", ["title": "Ship", "items": ["a", "b"]])
        let id = try XCTUnwrap((created["created"] as? [String: Any])?["id"] as? String)
        try call("check_item", ["id": id, "item": 1])
        let last = try call("check_item", ["id": id, "item": 2])
        XCTAssertEqual((last["task"] as? [String: Any])?["done"] as? Bool, true)
        XCTAssertNotNil(last["note"])
        let reopened = try call("check_item", ["id": id, "item": 2, "done": false])
        XCTAssertNil((reopened["task"] as? [String: Any])?["done"])
        XCTAssertTrue(error("check_item", ["id": id, "item": 3]).contains("1–2"))
    }

    func testUpdateAddsItemsAboveTheBlankRowAndClearsDue() throws {
        let note = Note(title: "Trip", bodyMarkdown: "- [x] Book\n- [ ] ", isChecklist: true, dueDate: day("2026-10-09"))
        note.done = true
        context.insert(note)
        try context.save()
        let out = try call("update_task", ["id": note.id.uuidString, "add_items": ["Pack"], "due": "none", "title": "Trip to KL"])
        XCTAssertEqual(note.bodyMarkdown, "- [x] Book\n- [ ] Pack\n- [ ] ")
        XCTAssertNil(note.dueDate)
        XCTAssertFalse(note.done, "an open step reopens a done task")
        XCTAssertEqual((out["updated"] as? [String: Any])?["title"] as? String, "Trip to KL")
        XCTAssertTrue(error("update_task", ["id": note.id.uuidString]).contains("Nothing to change"))
    }

    func testAddingItemsToAPlainNoteMakesItAChecklist() throws {
        let note = Note(title: "Plan", bodyMarkdown: "Some thoughts")
        context.insert(note)
        try context.save()
        try call("update_task", ["id": note.id.uuidString, "add_items": "Step one", "append_notes": "More"])
        XCTAssertTrue(note.isChecklist)
        XCTAssertEqual(note.bodyMarkdown, "Some thoughts\nMore\n- [ ] Step one")
    }

    func testCompleteArchiveAndShortIds() throws {
        let note = Note(title: "Pay rent")
        context.insert(note)
        try context.save()
        let short = String(note.id.uuidString.prefix(8))
        try call("complete_task", ["id": short])
        XCTAssertTrue(note.done)
        XCTAssertNotNil(note.completedAt)
        try call("complete_task", ["id": short, "done": false])
        XCTAssertFalse(note.done)
        try call("archive_task", ["id": note.id.uuidString])
        XCTAssertTrue(note.archived)
        XCTAssertFalse(note.deleted, "agents can't delete")
        XCTAssertEqual(try call("list_tasks", ["view": "all"])["total"] as? Int, 0)
    }

    func testRetriedCreateReturnsTheSameTask() throws {
        let first = try call("create_task", ["title": "Call mom"])
        let again = try call("create_task", ["title": " call MOM "])
        XCTAssertEqual((again["task"] as? [String: Any])?["id"] as? String,
                       (first["created"] as? [String: Any])?["id"] as? String)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 1)
    }

    func testReadOnlyRefusesWritesButAllowsReads() throws {
        allowWrites = false
        XCTAssertTrue(error("create_task", ["title": "x"]).contains("Settings"))
        XCTAssertNoThrow(try call("list_tasks"))
    }

    func testErrorsSayHowToFixTheCall() {
        XCTAssertTrue(error("create_task", ["title": "x", "due": "next friday"]).contains("YYYY-MM-DD"))
        XCTAssertTrue(error("create_task", ["title": "x", "due": "2026-02-30"]).contains("YYYY-MM-DD"))
        XCTAssertTrue(error("create_task", [:]).contains("`title` is required"))
        XCTAssertTrue(error("get_task", ["id": UUID().uuidString]).contains("list_tasks"))
        XCTAssertTrue(error("list_tasks", ["view": "week"]).contains("today, upcoming"))
        XCTAssertTrue(error("delete_task").contains("Unknown tool"))
        XCTAssertTrue(runner.run(tool: "list_tasks", arguments: "[1]").result.isError)
    }

    func testChangesAreReportedForWritesOnly() throws {
        let out = runner.run(tool: "create_task", arguments: #"{"title":"New"}"#)
        XCTAssertEqual(out.changes.map(\.kind), [.created])
        XCTAssertTrue(runner.run(tool: "list_tasks", arguments: "{}").changes.isEmpty)
    }

    func testNotesShowImagesAsPlaceholders() {
        let body = "Look:\n" + NoteImageMarkup.line(NoteImageRef(id: UUID())) + "\n- [ ] Fix it"
        XCTAssertEqual(AgentTaskBody.notes(in: body), "Look:\n[image]")
        XCTAssertEqual(AgentTaskBody.items(in: body).map(\.text), ["Fix it"])
    }

    func testBannerWording() {
        let a = UUID(), b = UUID()
        let one = AgentActivityAnnouncer.message(
            for: [AgentChange(kind: .created, noteID: a, title: "Gym", dueDate: nil, done: false),
                  AgentChange(kind: .updated, noteID: a, title: "Gym", dueDate: nil, done: false)],
            by: AgentClient("claude-code"), zh: true)
        XCTAssertEqual(one.title, "Claude Code 新建了「Gym」")
        XCTAssertEqual(one.clickAction, .openNote(id: a))
        XCTAssertEqual(one.source, .claudeCode)

        let many = AgentActivityAnnouncer.message(
            for: [AgentChange(kind: .completed, noteID: a, title: "A", dueDate: nil, done: true),
                  AgentChange(kind: .completed, noteID: b, title: "B", dueDate: nil, done: true)],
            by: AgentClient("codex-mcp-client"), zh: false)
        XCTAssertEqual(many.title, "Codex completed 2 tasks")
        XCTAssertEqual(many.body, "A, B")
        XCTAssertNil(many.clickAction)
    }
}
