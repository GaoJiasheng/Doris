import Foundation
import SwiftData
import DorisCore

/// Writes this Mac's `ActivityDay` rows — the synced counters behind the
/// Stats tab, the notch numbers and the iPhone's read-only view.
///
/// One recorder per launch is one *session*: it creates its own row per day
/// and only ever writes the rows it created (see `ActivityDay` for why that
/// keeps two Macs, or two launches, from conflicting or double counting).
@MainActor
final class ActivityRecorder {
    private(set) static var shared: ActivityRecorder?

    static func start(container: ModelContainer) {
        guard shared == nil else { return }
        let r = ActivityRecorder(container: container)
        shared = r
        r.begin()
    }

    private let context: ModelContext
    private let session = UUID()
    /// This session's row for each day it has recorded something.
    private var rows: [String: ActivityDay] = [:]
    private var dirty = false
    private var timers: [Timer] = []

    private init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func begin() {
        timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { ActivityRecorder.shared?.flush() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { ActivityRecorder.shared?.syncTokens() }
        })
        // Token history is already on disk; publish it once the collector's
        // first pass has had time to run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.syncTokens() }
    }

    // MARK: Recording

    func addWords(_ n: Int, at date: Date = Date()) {
        guard n > 0 else { return }
        row(for: date).typedWords += n
        dirty = true
    }

    /// Gives back words just credited (a typo fixed). Never below zero:
    /// the give-back is capped by recent credits, which may sit in
    /// yesterday's row right after midnight.
    func removeWords(_ n: Int, at date: Date = Date()) {
        guard n > 0 else { return }
        let r = row(for: date)
        let next = max(0, r.typedWords - n)
        guard next != r.typedWords else { return }
        r.typedWords = next
        dirty = true
    }

    /// Sets this Mac's typed words for `date`'s day back to zero, in every
    /// row it wrote that day. Rows from its earlier launches have no other
    /// writer (one Doris per Mac), so changing them can't collide.
    func clearWords(on date: Date = Date()) {
        let key = ActivityTotals.dayKey(date)
        let me = ActivityDevice.key
        let mine = (try? context.fetch(FetchDescriptor<ActivityDay>(
            predicate: #Predicate { $0.deviceKey == me && $0.day == key }))) ?? []
        for r in mine + [rows[key]].compactMap({ $0 }) where r.typedWords != 0 {
            r.typedWords = 0
            dirty = true
        }
        flush()
    }

    /// Marks the 30 s slot containing `date` as spent in a meeting.
    func markMeeting(at date: Date = Date()) {
        let r = row(for: date)
        var bits = r.meetingSlots
        let i = ActivityTotals.slotIndex(at: date, dayStart: r.dayStart)
        let before = bits
        ActivityTotals.setSlot(i, in: &bits)
        guard bits != before else { return }
        r.meetingSlots = bits
        dirty = true
    }

    /// Saves pending changes; the 60 s `SyncTimer` poke exports them.
    func flush() {
        guard dirty else { return }
        let now = Date()
        // Only what changed: this session may hold hundreds of history rows,
        // and touching one uploads it again.
        for case let r as ActivityDay in context.changedModelsArray { r.updatedAt = now }
        do {
            try context.save()
            dirty = false
        } catch {
            NSLog("[Activity] save failed: \(error)")
        }
    }

    private func row(for date: Date) -> ActivityDay {
        let key = ActivityTotals.dayKey(date)
        if let r = rows[key] { return r }
        let r = ActivityDay(deviceKey: ActivityDevice.key, deviceName: ActivityDevice.name,
                            session: session, day: key, dayStart: Calendar.current.startOfDay(for: date))
        context.insert(r)
        rows[key] = r
        return r
    }

    // MARK: Tokens

    /// Publishes this Mac's per-day token totals, all history, with their
    /// split by tool and model, where they exceed what any of its rows
    /// already report. Snapshots merge by max, so re-publishing the same
    /// number is harmless — skipping it just keeps old days from growing a
    /// row per launch.
    func syncTokens() {
        guard let tokenContainer = TokenStore.shared else { return }
        let cal = Calendar.current
        let tokenCtx = ModelContext(tokenContainer)
        let daily = (try? tokenCtx.fetch(FetchDescriptor<TokenUsageDaily>())) ?? []
        struct Local { var tokens = 0, cost = 0.0, start: Date, detail: [TokenDetailEntry] = [] }
        var local: [String: Local] = [:]
        for d in daily where d.billableTokens > 0 || d.costUSD > 0 {
            let start = cal.startOfDay(for: d.day)
            let k = ActivityTotals.dayKey(start)
            var v = local[k] ?? Local(start: start)
            v.tokens += d.billableTokens
            v.cost += d.costUSD
            v.detail.append(TokenDetailEntry(tool: d.tool.displayName, model: d.model, tokens: d.billableTokens,
                                             cost: d.costUSD, calls: d.callCount))
            local[k] = v
        }
        guard !local.isEmpty else { return }

        let me = ActivityDevice.key
        let mine = (try? context.fetch(FetchDescriptor<ActivityDay>(
            predicate: #Predicate { $0.deviceKey == me }))) ?? []
        var reported: [String: (tokens: Int, cost: Double, detail: Bool)] = [:]
        for r in mine {
            let prev = reported[r.day] ?? (0, 0, false)
            reported[r.day] = (max(prev.tokens, r.tokens), max(prev.cost, r.tokenCostUSD),
                               prev.detail || !r.tokenDetail.isEmpty)
        }
        for (day, v) in local {
            let seen = reported[day] ?? (0, 0, false)
            guard v.tokens > seen.tokens || v.cost > seen.cost + 0.000_1 || !seen.detail else { continue }
            let r = row(for: v.start)
            r.tokens = max(r.tokens, v.tokens)
            r.tokenCostUSD = max(r.tokenCostUSD, v.cost)
            r.tokenDetail = ActivityTotals.encodeDetail(v.detail)
            dirty = true
        }
        flush()
    }
}
