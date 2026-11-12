import XCTest
@testable import DorisCore

final class ActivityTotalsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    private lazy var day = cal.date(from: DateComponents(year: 2026, month: 11, day: 5))!
    private var key: String { ActivityTotals.dayKey(day, calendar: cal) }

    private func slots(_ range: Range<Int>) -> Data {
        var d = Data()
        for i in range { ActivityTotals.setSlot(i, in: &d) }
        return d
    }

    func testTwoMacsAdd() {
        // Mac A: 3000 words, 1 h meeting 09:00–10:00. Mac B: 2000 words, 1 h 14:00–15:00.
        let a = ActivityRecord(deviceKey: "A", day: key, dayStart: day, typedWords: 3000,
                               meetingSlots: slots(1080..<1200))
        let b = ActivityRecord(deviceKey: "B", day: key, dayStart: day, typedWords: 2000,
                               meetingSlots: slots(1680..<1800))
        let t = ActivityTotals.byDay([a, b], calendar: cal)[key]!
        XCTAssertEqual(t.typedWords, 5000)
        XCTAssertEqual(t.meetingSeconds, 2 * 3600)
    }

    func testSessionsOfOneMacAdd() {
        // Doris relaunched mid-day: two session rows, disjoint increments.
        let s1 = ActivityRecord(deviceKey: "A", day: key, dayStart: day, typedWords: 1200)
        let s2 = ActivityRecord(deviceKey: "A", day: key, dayStart: day, typedWords: 800)
        XCTAssertEqual(ActivityTotals.byDay([s1, s2], calendar: cal)[key]!.typedWords, 2000)
    }

    func testTokenSnapshotsTakeMaxPerMac() {
        // Two sessions on Mac A saw 1.0M then 1.5M; Mac B saw 0.4M.
        let rows = [
            ActivityRecord(deviceKey: "A", day: key, dayStart: day, tokens: 1_000_000, tokenCostUSD: 2),
            ActivityRecord(deviceKey: "A", day: key, dayStart: day, tokens: 1_500_000, tokenCostUSD: 3),
            ActivityRecord(deviceKey: "B", day: key, dayStart: day, tokens: 400_000, tokenCostUSD: 1),
        ]
        let t = ActivityTotals.byDay(rows, calendar: cal)[key]!
        XCTAssertEqual(t.tokens, 1_900_000)
        XCTAssertEqual(t.tokenCostUSD, 4, accuracy: 0.0001)
    }

    func testOverlappingMeetingCountsOnce() {
        // The same meeting open on two Macs: 10:00–10:30 on A, 10:15–10:45 on B → 45 min.
        let a = ActivityRecord(deviceKey: "A", day: key, dayStart: day, meetingSlots: slots(1200..<1260))
        let b = ActivityRecord(deviceKey: "B", day: key, dayStart: day, meetingSlots: slots(1230..<1290))
        XCTAssertEqual(ActivityTotals.byDay([a, b], calendar: cal)[key]!.meetingSeconds, 45 * 60)
    }

    func testDuplicateRowIsIdempotentForSnapshotsAndSlots() {
        let r = ActivityRecord(deviceKey: "A", day: key, dayStart: day, tokens: 10, meetingSlots: slots(0..<4))
        let t = ActivityTotals.byDay([r, r], calendar: cal)[key]!
        XCTAssertEqual(t.tokens, 10)
        XCTAssertEqual(t.meetingSeconds, 120)
    }

    func testDeviceFilter() {
        let a = ActivityRecord(deviceKey: "A", day: key, dayStart: day, typedWords: 3)
        let b = ActivityRecord(deviceKey: "B", day: key, dayStart: day, typedWords: 4)
        XCTAssertEqual(ActivityTotals.byDay([a, b], deviceKey: "B", calendar: cal)[key]!.typedWords, 4)
    }

    func testSummary() {
        let now = cal.date(byAdding: .hour, value: 12, to: day)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)!
        let rows = [
            ActivityRecord(deviceKey: "A", day: key, dayStart: day, typedWords: 700),
            ActivityRecord(deviceKey: "A", day: ActivityTotals.dayKey(yesterday, calendar: cal),
                           dayStart: yesterday, typedWords: 700),
        ]
        let s = ActivityTotals.summary(ActivityTotals.byDay(rows, calendar: cal), now: now, calendar: cal)
        XCTAssertEqual(s.today.typedWords, 700)
        XCTAssertEqual(s.week.typedWords, 1400)
        XCTAssertEqual(s.average.typedWords, 200)
    }

    func testWordCount() {
        XCTAssertEqual(WordCount.count("今天天气不错 hello world"), 8)
        XCTAssertEqual(WordCount.count("GPT-5 发布了！"), 5)
        XCTAssertEqual(WordCount.count("，。 !? 🙂"), 0)
    }

    func testOnlyTextKeysCountAsTyping() {
        XCTAssertTrue(TypingRules.isTypingKey(code: 0, command: false, control: false))     // a
        XCTAssertTrue(TypingRules.isTypingKey(code: 51, command: false, control: false))    // delete
        XCTAssertTrue(TypingRules.isTypingKey(code: 49, command: false, control: false))    // space
        XCTAssertFalse(TypingRules.isTypingKey(code: 125, command: false, control: false))  // ↓
        XCTAssertFalse(TypingRules.isTypingKey(code: 121, command: false, control: false))  // page down
        XCTAssertFalse(TypingRules.isTypingKey(code: 40, command: true, control: false))    // ⌘K
        XCTAssertFalse(TypingRules.isTypingKey(code: 49, command: false, control: true))    // ⌃Space
    }

    func testAllowanceFollowsKeys() {
        XCTAssertEqual(TypingRules.allowance(keys: 0), 2)
        XCTAssertEqual(TypingRules.allowance(keys: 1), 6)    // one key picking a phrase
        XCTAssertLessThan(TypingRules.allowance(keys: 3), 1_000)
    }

    // MARK: Periods

    private func total(_ words: Int) -> ActivityTotal { ActivityTotal(typedWords: words) }
    private func key(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }

    func testPeriodsSumTheRightDays() {
        let totals = [key(2026, 11, 5): total(1), key(2026, 11, 4): total(2),
                      key(2026, 10, 30): total(4), key(2026, 10, 7): total(8), key(2026, 1, 1): total(16)]
        XCTAssertEqual(ActivityTotals.total(totals, .today, now: day, calendar: cal).typedWords, 1)
        XCTAssertEqual(ActivityTotals.total(totals, .week, now: day, calendar: cal).typedWords, 7)
        XCTAssertEqual(ActivityTotals.total(totals, .month, now: day, calendar: cal).typedWords, 15)
        XCTAssertEqual(ActivityTotals.total(totals, .all, now: day, calendar: cal).typedWords, 31)
    }

    func testAllTimeAverageRunsFromFirstData() {
        let totals = [key(2026, 11, 3): total(30)]
        XCTAssertEqual(ActivityTotals.dayCount(totals, .all, now: day, calendar: cal), 3)
        XCTAssertEqual(ActivityTotals.dayCount([:], .all, now: day, calendar: cal), 1)
    }

    func testBarsGoMonthlyPastSixtyDays() {
        let short = ActivityTotals.bars([key(2026, 11, 1): total(1)], .all, now: day, calendar: cal)
        XCTAssertFalse(short.byMonth)
        XCTAssertEqual(short.points.count, 7)
        let long = ActivityTotals.bars([key(2026, 1, 15): total(5), key(2026, 1, 20): total(6), key(2026, 11, 5): total(1)],
                                       .all, now: day, calendar: cal)
        XCTAssertTrue(long.byMonth)
        XCTAssertEqual(long.points.count, 11)
        XCTAssertEqual(long.points.first?.total.typedWords, 11)
        XCTAssertEqual(long.points.last?.total.typedWords, 1)
    }

    // MARK: Token detail

    private func detail(_ tokens: Int, tool: String = "Claude Code", model: String = "m") -> Data {
        ActivityTotals.encodeDetail([TokenDetailEntry(tool: tool, model: model, tokens: tokens, cost: Double(tokens) / 100, calls: 1)])
    }

    func testDetailTakesMaxPerMacThenSumsAcrossMacs() {
        // Mac A reported the same day from two launches; Mac B once.
        let a1 = ActivityRecord(deviceKey: "A", day: key, dayStart: day, tokenDetail: detail(100))
        let a2 = ActivityRecord(deviceKey: "A", day: key, dayStart: day, tokenDetail: detail(150))
        let b = ActivityRecord(deviceKey: "B", day: key, dayStart: day, tokenDetail: detail(50))
        let all = ActivityTotals.tokenDetail([a1, a2, b], .today, now: day, calendar: cal)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].tokens, 200)
        let onlyA = ActivityTotals.tokenDetail([a1, a2, b], .today, deviceKey: "A", now: day, calendar: cal)
        XCTAssertEqual(onlyA[0].tokens, 150)
    }

    func testDetailRespectsPeriodAndKeepsModelsApart() {
        let old = cal.date(byAdding: .day, value: -40, to: day)!
        let r1 = ActivityRecord(deviceKey: "A", day: key, dayStart: day, tokenDetail: detail(10, model: "x"))
        let r2 = ActivityRecord(deviceKey: "A", day: ActivityTotals.dayKey(old, calendar: cal), dayStart: old,
                                tokenDetail: detail(20, model: "y"))
        XCTAssertEqual(ActivityTotals.tokenDetail([r1, r2], .month, now: day, calendar: cal).map(\.model), ["x"])
        XCTAssertEqual(ActivityTotals.tokenDetail([r1, r2], .all, now: day, calendar: cal).map(\.model), ["y", "x"])
    }
}
