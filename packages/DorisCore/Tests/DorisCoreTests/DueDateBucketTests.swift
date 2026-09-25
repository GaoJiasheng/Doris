import XCTest
@testable import DorisCore

/// The "今日" glance surfaces (macOS desktop card, iOS widget) list what is
/// due today or overdue and fold everything later under "之后". These pin
/// the day boundaries that split the two.
final class DueDateBucketTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return c
    }()

    /// 2026-09-25 15:00 local.
    private var now: Date { at(2026, 9, 25, 15, 0) }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func note(due: Date?, done: Bool = false) -> Note {
        let n = Note(title: "t", dueDate: due)
        n.done = done
        return n
    }

    func testTodayCoversTheWholeDay() {
        for due in [at(2026, 9, 25, 0, 0), at(2026, 9, 25, 9, 0), at(2026, 9, 25, 23, 59)] {
            let n = note(due: due)
            XCTAssertTrue(n.isDueToday(now: now, calendar: cal), "\(due)")
            XCTAssertFalse(n.isDueAfterToday(now: now, calendar: cal), "\(due)")
            // Earlier today is not overdue — it stays in the today list,
            // without a red date.
            XCTAssertFalse(n.isOverdue(now: now, calendar: cal), "\(due)")
        }
    }

    func testMidnightStartsLater() {
        let n = note(due: at(2026, 9, 26, 0, 0))
        XCTAssertFalse(n.isDueToday(now: now, calendar: cal))
        XCTAssertTrue(n.isDueAfterToday(now: now, calendar: cal))
    }

    func testOverdueStaysInTheTodayList() {
        let n = note(due: at(2026, 9, 20, 10, 0))
        XCTAssertFalse(n.isDueToday(now: now, calendar: cal))
        XCTAssertFalse(n.isDueAfterToday(now: now, calendar: cal))
        XCTAssertTrue(n.isOverdue(now: now, calendar: cal))
    }

    func testPastAndDoneDropsOut() {
        let n = note(due: at(2026, 9, 20, 10, 0), done: true)
        XCTAssertTrue(n.isPastAndCompleted(now: now, calendar: cal))
        XCTAssertFalse(n.isOverdue(now: now, calendar: cal))
    }

    func testUndatedIsNeither() {
        let n = note(due: nil)
        XCTAssertFalse(n.isDueToday(now: now, calendar: cal))
        XCTAssertFalse(n.isDueAfterToday(now: now, calendar: cal))
        XCTAssertFalse(n.isOverdue(now: now, calendar: cal))
    }
}
