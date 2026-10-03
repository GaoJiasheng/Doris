import XCTest
import SwiftData
@testable import DorisCore

@MainActor
final class CompletionTests: XCTestCase {
    /// The bug: a fully-ticked checklist reopened with the Done toggle kept
    /// showing as completed on every card.
    func testReopeningAFullyTickedChecklistSticks() {
        let note = Note(title: "hexa 修正", bodyMarkdown: "- [x] a\n- [x] b", isChecklist: true)
        note.done = true
        XCTAssertTrue(note.isCompleted)
        note.done = false
        XCTAssertFalse(note.isCompleted)
        XCTAssertEqual(note.checklistProgress?.done, 2, "progress still reads 2/2")
    }
}
