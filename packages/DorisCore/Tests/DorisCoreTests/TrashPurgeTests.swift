import XCTest
import SwiftData
@testable import DorisCore

/// The sync cycle's purge empties the trash and nothing else. It used to
/// also hard-delete archived notes 30 days after their last edit, which
/// silently wiped users' archives.
@MainActor
final class TrashPurgeTests: XCTestCase {
    func testPurgesOnlyTrashOlderThanADay() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let ctx = container.mainContext
        let now = Date()
        func note(_ title: String, archived: Bool = false, deleted: Bool = false, age days: Double) -> Note {
            let n = Note(title: title)
            n.archived = archived
            n.deleted = deleted
            n.updatedAt = now.addingTimeInterval(-days * 86_400)
            ctx.insert(n)
            return n
        }
        _ = note("archived a year ago", archived: true, age: 365)
        _ = note("archived yesterday", archived: true, age: 1)
        _ = note("active, untouched for months", age: 120)
        _ = note("trashed 2 days ago", deleted: true, age: 2)
        _ = note("archived, then trashed 2 days ago", archived: true, deleted: true, age: 2)
        _ = note("trashed an hour ago", deleted: true, age: 1.0 / 24)
        try ctx.save()

        SyncTimer.purgeTombstones(context: ctx, now: now)

        let left = Set(try ctx.fetch(FetchDescriptor<Note>()).map(\.title))
        XCTAssertEqual(left, ["archived a year ago", "archived yesterday",
                              "active, untouched for months", "trashed an hour ago"])
    }
}
