import XCTest
@testable import DorisCore

final class NoteInlineMarkupTests: XCTestCase {
    typealias M = NoteInlineMarkup
    typealias S = NoteInlineMarkup.Style

    func testParsesEachStyle() {
        XCTAssertEqual(M.parse(line: "a **b** c"),
                       [.init("a "), .init("b", S(bold: true)), .init(" c")])
        XCTAssertEqual(M.parse(line: "<u>x</u>"), [.init("x", S(underline: true))])
        XCTAssertEqual(M.parse(line: "<mark green>go</mark>!"),
                       [.init("go", S(highlight: .green)), .init("!")])
    }

    func testNestedStyles() {
        let runs = M.parse(line: "**bold <u>both</u>** <mark red><u>u</u></mark>")
        XCTAssertEqual(runs, [
            .init("bold ", S(bold: true)),
            .init("both", S(bold: true, underline: true)),
            .init(" "),
            .init("u", S(underline: true, highlight: .red)),
        ])
    }

    func testUnclosedMarksAreText() {
        XCTAssertEqual(M.parse(line: "2 ** 3"), [.init("2 ** 3")])
        XCTAssertEqual(M.parse(line: "a <u>b"), [.init("a <u>b")])
        XCTAssertEqual(M.parse(line: "<mark blue>x</mark>"), [.init("<mark blue>x</mark>")])
        XCTAssertEqual(M.parse(line: "x < y"), [.init("x < y")])
    }

    func testRoundTrips() {
        let lines = [
            "plain",
            "a **b** c",
            "**bold <u>both</u>** tail",
            "<mark yellow>hi</mark><mark red>there</mark>",
            "<u>**x**</u>",
            "",
            "中文 **加粗** 和 <mark green>高亮</mark>",
        ]
        for line in lines {
            let runs = M.parse(line: line)
            XCTAssertEqual(M.parse(line: M.serialize(runs)), runs, line)
        }
    }

    func testLiteralMarkersSurviveARoundTrip() {
        for text in ["2 ** 3 **", "type <u> to underline", "C:\\\\path", "a\\*b", "<mark red>"] {
            let saved = M.serialize([.init(text)])
            XCTAssertEqual(M.parse(line: saved), [.init(text)], "\(text) → \(saved)")
        }
    }

    /// Text that only looks like a mark is saved as it was — no escapes —
    /// so opening an old note doesn't rewrite it.
    func testUnambiguousTextIsNotEscaped() {
        for text in ["2 ** 3", "a <u> b", "x < y", "C:\\dir", "**"] {
            XCTAssertEqual(M.serialize([.init(text)]), text)
        }
    }

    func testSerializeNestsAndCloses() {
        XCTAssertEqual(M.serialize([.init("a", S(bold: true, underline: true)), .init("b", S(bold: true))]),
                       "**<u>a</u>b**")
        XCTAssertEqual(M.serialize([.init("x", S(highlight: .red)), .init("y", S(highlight: .green))]),
                       "<mark red>x</mark><mark green>y</mark>")
    }

    func testPlainAndDisplayText() {
        XCTAssertEqual(M.plain("**a** <u>b</u>\n<mark red>c</mark>"), "a b\nc")
        XCTAssertEqual(NoteImageMarkup.displayText("**hi**", placeholder: "[img]"), "hi")
    }
}
