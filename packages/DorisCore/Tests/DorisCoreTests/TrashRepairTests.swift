import XCTest
@testable import DorisCore

final class TrashRepairTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)

    func testTrashedAndUntouchedGoesBackToTrash() {
        XCTAssertEqual(TrashRepair.decide(deleted: false, deletedAt: t, updatedAt: t), .trash)
        XCTAssertEqual(TrashRepair.decide(deleted: true, deletedAt: t, updatedAt: t.addingTimeInterval(5)), .trash)
    }

    func testEditedAfterTrashIsKept() {
        // Brought back by the bug and used since.
        XCTAssertEqual(TrashRepair.decide(deleted: false, deletedAt: t, updatedAt: t.addingTimeInterval(3600)), .keep)
    }

    func testNeverTrashedIsLeftAlone() {
        XCTAssertEqual(TrashRepair.decide(deleted: false, deletedAt: nil, updatedAt: t), .leave)
    }

    func testOldFlagWithoutStampIsTrash() {
        XCTAssertEqual(TrashRepair.decide(deleted: true, deletedAt: nil, updatedAt: t), .trash)
    }

    func testTrashStateIsDeletedAt() {
        let n = Note(title: "x")
        XCTAssertFalse(n.isTrashed)
        n.deletedAt = t
        XCTAssertTrue(n.isTrashed)
        n.deleted = true
        n.deletedAt = nil
        XCTAssertFalse(n.isTrashed, "the unsynced flag alone isn't the trash")
    }
}
