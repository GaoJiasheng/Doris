import Foundation
import SwiftData

/// One Mac's activity on one local day — typed words, AI tokens and meeting
/// time — synced through CloudKit so every device can show the total across
/// Macs. Only Macs write these; the iPhone just reads them.
///
/// The sync rules are what keep two Macs from conflicting or counting
/// anything twice. Each field merges its own way (see `ActivityTotals`):
///
/// - **Typed words are increments.** A row belongs to one *session* (one
///   launch of Doris on one Mac, on one day) and only that running process
///   ever writes it: it holds the object it created and never looks rows up
///   to update them. A word is added to exactly one row, so the total is
///   the plain sum over all rows — no two writers, no lost updates, and a
///   reinstall or a wiped local store just starts new rows instead of
///   overwriting old ones.
/// - **Tokens are snapshots.** They're re-read from the Mac's own AI-tool
///   logs, so every row from one Mac for one day reports the *same*
///   quantity, possibly at different moments. Merge: the largest per
///   (`deviceKey`, `day`), then the sum across Macs. `deviceKey` comes from
///   the hardware, so two Macs never share one even after Migration
///   Assistant copies the app's data across.
///   `tokenDetail` splits the same snapshot by tool and model and merges the
///   same way, per (`deviceKey`, `day`, tool, model).
/// - **Meetings are time slots.** `meetingSlots` is a bitmap of the 30 s
///   slots since `dayStart` that the Mac spent in a meeting. Merge: the
///   union of the slots, by absolute time. The same minute in a meeting on
///   two Macs at once counts once.
///
/// CloudKit-backed SwiftData allows no unique constraints and needs every
/// attribute optional or defaulted, hence the plain defaults.
@Model
public final class ActivityDay {
    public var id: UUID = UUID()
    /// Stable per machine (hashed hardware UUID).
    public var deviceKey: String = ""
    public var deviceName: String = ""
    /// One launch of Doris; rows are written only by the session that made them.
    public var session: UUID = UUID()
    /// "yyyy-MM-dd" in the recording Mac's time zone.
    public var day: String = ""
    /// The recording Mac's local midnight for `day` — anchors `meetingSlots`.
    public var dayStart: Date = Date()
    /// Words in the text this session produced: each CJK character counts
    /// one, each run of Latin letters or digits counts one.
    public var typedWords: Int = 0
    /// Snapshot of this Mac's billable tokens for `day`.
    public var tokens: Int = 0
    public var tokenCostUSD: Double = 0
    /// JSON `[TokenDetailEntry]`: `tokens` split by tool and model.
    public var tokenDetail: Data = Data()
    /// Bit i set = in a meeting during [dayStart + 30·i s, +30 s).
    public var meetingSlots: Data = Data()
    public var updatedAt: Date = Date()

    public init(deviceKey: String, deviceName: String, session: UUID, day: String, dayStart: Date) {
        self.deviceKey = deviceKey
        self.deviceName = deviceName
        self.session = session
        self.day = day
        self.dayStart = dayStart
    }
}
