import Foundation

/// A value copy of an `ActivityDay` row, so the merge rules are pure and
/// testable without a SwiftData context.
public struct ActivityRecord: Sendable, Equatable {
    public var deviceKey: String
    public var deviceName: String
    public var day: String
    public var dayStart: Date
    public var typedWords: Int
    public var tokens: Int
    public var tokenCostUSD: Double
    public var tokenDetail: Data
    public var meetingSlots: Data

    public init(deviceKey: String, deviceName: String = "", day: String, dayStart: Date,
                typedWords: Int = 0, tokens: Int = 0, tokenCostUSD: Double = 0,
                tokenDetail: Data = Data(), meetingSlots: Data = Data()) {
        self.deviceKey = deviceKey
        self.deviceName = deviceName
        self.day = day
        self.dayStart = dayStart
        self.typedWords = typedWords
        self.tokens = tokens
        self.tokenCostUSD = tokenCostUSD
        self.tokenDetail = tokenDetail
        self.meetingSlots = meetingSlots
    }

    public init(_ row: ActivityDay) {
        self.init(deviceKey: row.deviceKey, deviceName: row.deviceName, day: row.day, dayStart: row.dayStart,
                  typedWords: row.typedWords, tokens: row.tokens, tokenCostUSD: row.tokenCostUSD,
                  tokenDetail: row.tokenDetail, meetingSlots: row.meetingSlots)
    }
}

public struct ActivityTotal: Sendable, Equatable {
    public var typedWords = 0
    public var tokens = 0
    public var tokenCostUSD = 0.0
    public var meetingSeconds = 0

    public init(typedWords: Int = 0, tokens: Int = 0, tokenCostUSD: Double = 0, meetingSeconds: Int = 0) {
        self.typedWords = typedWords
        self.tokens = tokens
        self.tokenCostUSD = tokenCostUSD
        self.meetingSeconds = meetingSeconds
    }

    public static func + (a: ActivityTotal, b: ActivityTotal) -> ActivityTotal {
        ActivityTotal(typedWords: a.typedWords + b.typedWords, tokens: a.tokens + b.tokens,
                      tokenCostUSD: a.tokenCostUSD + b.tokenCostUSD,
                      meetingSeconds: a.meetingSeconds + b.meetingSeconds)
    }
}

/// One tool + model's share of a Mac's token snapshot for a day.
public struct TokenDetailEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { tool + "|" + model }
    /// The tool's display name ("Claude Code"). Stored as text because the
    /// tool list only exists on the Mac and the iPhone shows these too.
    public var tool: String
    public var model: String
    public var tokens: Int
    public var cost: Double
    public var calls: Int

    public init(tool: String, model: String, tokens: Int, cost: Double, calls: Int) {
        self.tool = tool; self.model = model; self.tokens = tokens; self.cost = cost; self.calls = calls
    }
}

/// The ranges the Stats page offers.
public enum ActivityPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month, all
    public var id: String { rawValue }
}

/// Bars for a chart: one per day, or one per month for long histories.
public struct ActivityBars: Sendable {
    public var byMonth: Bool
    public var points: [(start: Date, total: ActivityTotal)]
}

/// The merge rules for `ActivityDay` rows (why they can't conflict or
/// double count is spelled out on `ActivityDay`).
public enum ActivityTotals {
    public static let slotSeconds = 30

    // MARK: Days

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Meeting slot bitmap

    public static func slotIndex(at date: Date, dayStart: Date) -> Int {
        max(0, Int(date.timeIntervalSince(dayStart)) / slotSeconds)
    }

    public static func setSlot(_ i: Int, in data: inout Data) {
        guard i >= 0 else { return }
        let byte = i / 8
        if data.count <= byte { data.append(Data(count: byte + 1 - data.count)) }
        data[data.startIndex + byte] |= UInt8(1) << UInt8(i % 8)
    }

    public static func slots(_ data: Data) -> [Int] {
        var out: [Int] = []
        for (b, byte) in data.enumerated() where byte != 0 {
            for bit in 0..<8 where byte & (UInt8(1) << UInt8(bit)) != 0 { out.append(b * 8 + bit) }
        }
        return out
    }

    // MARK: Merge

    /// Totals per local day (in `calendar`'s time zone), keyed "yyyy-MM-dd".
    /// Pass `deviceKey` to restrict to one Mac.
    public static func byDay(_ records: [ActivityRecord], deviceKey: String? = nil,
                             calendar: Calendar = .current) -> [String: ActivityTotal] {
        let rows = deviceKey.map { k in records.filter { $0.deviceKey == k } } ?? records
        var out: [String: ActivityTotal] = [:]

        // Typed words: increments, one row per session → plain sum.
        for r in rows where r.typedWords > 0 {
            out[r.day, default: ActivityTotal()].typedWords += r.typedWords
        }

        // Tokens: snapshots → max per (Mac, day), then sum across Macs.
        var snap: [String: (tokens: Int, cost: Double)] = [:]
        for r in rows where r.tokens > 0 || r.tokenCostUSD > 0 {
            let k = r.deviceKey + "|" + r.day
            let prev = snap[k] ?? (0, 0)
            snap[k] = (max(prev.tokens, r.tokens), max(prev.cost, r.tokenCostUSD))
        }
        for (k, v) in snap {
            let day = String(k[k.index(after: k.firstIndex(of: "|")!)...])
            out[day, default: ActivityTotal()].tokens += v.tokens
            out[day, default: ActivityTotal()].tokenCostUSD += v.cost
        }

        // Meetings: union of absolute 30 s slots, then bucket by local day.
        var absolute = Set<Int>()
        for r in rows where !r.meetingSlots.isEmpty {
            let base = Int(r.dayStart.timeIntervalSince1970) / slotSeconds
            for i in slots(r.meetingSlots) { absolute.insert(base + i) }
        }
        for s in absolute {
            let day = dayKey(Date(timeIntervalSince1970: TimeInterval(s * slotSeconds)), calendar: calendar)
            out[day, default: ActivityTotal()].meetingSeconds += slotSeconds
        }
        return out
    }

    /// The last `days` local days, oldest first, zero-filled.
    public static func series(_ totals: [String: ActivityTotal], days: Int, now: Date = Date(),
                              calendar: Calendar = .current) -> [(day: Date, total: ActivityTotal)] {
        let sod = calendar.startOfDay(for: now)
        return stride(from: days - 1, through: 0, by: -1).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: sod) else { return nil }
            return (d, totals[dayKey(d, calendar: calendar)] ?? ActivityTotal())
        }
    }

    /// Today, the last-7-days sum and its daily average (sum ÷ 7).
    public static func summary(_ totals: [String: ActivityTotal], now: Date = Date(),
                               calendar: Calendar = .current) -> (today: ActivityTotal, week: ActivityTotal, average: ActivityTotal) {
        let week = series(totals, days: 7, now: now, calendar: calendar)
        let sum = week.reduce(ActivityTotal()) { $0 + $1.total }
        let avg = ActivityTotal(typedWords: sum.typedWords / 7, tokens: sum.tokens / 7,
                                tokenCostUSD: sum.tokenCostUSD / 7, meetingSeconds: sum.meetingSeconds / 7)
        return (week.last?.total ?? ActivityTotal(), sum, avg)
    }

    // MARK: Periods

    /// First day of a period as a day key; nil for all time. Keys sort like dates.
    public static func cutoffKey(_ period: ActivityPeriod, now: Date = Date(),
                                 calendar: Calendar = .current) -> String? {
        let back: Int
        switch period {
        case .today: back = 0
        case .week:  back = 6
        case .month: back = 29
        case .all:   return nil
        }
        let sod = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -back, to: sod).map { dayKey($0, calendar: calendar) }
    }

    /// Sum over a period.
    public static func total(_ totals: [String: ActivityTotal], _ period: ActivityPeriod,
                             now: Date = Date(), calendar: Calendar = .current) -> ActivityTotal {
        let cutoff = cutoffKey(period, now: now, calendar: calendar)
        let end = dayKey(now, calendar: calendar)
        return totals.reduce(ActivityTotal()) { sum, e in
            (cutoff.map { e.key >= $0 } ?? true) && e.key <= end ? sum + e.value : sum
        }
    }

    /// How many days a period's sum spreads over, for a daily average. All
    /// time runs from the first day with data; at least 1.
    public static func dayCount(_ totals: [String: ActivityTotal], _ period: ActivityPeriod,
                                now: Date = Date(), calendar: Calendar = .current) -> Int {
        switch period {
        case .today: return 1
        case .week:  return 7
        case .month: return 30
        case .all:
            guard let first = firstDay(totals, calendar: calendar) else { return 1 }
            let days = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: now)).day ?? 0
            return max(1, days + 1)
        }
    }

    /// Chart bars: today and 7 days chart the last week, 30 days the last
    /// month, all time everything since the first data — by month once that
    /// passes 60 days, where daily bars would be too thin to read.
    public static func bars(_ totals: [String: ActivityTotal], _ period: ActivityPeriod,
                            now: Date = Date(), calendar: Calendar = .current) -> ActivityBars {
        func daily(_ days: Int) -> ActivityBars {
            let points = series(totals, days: days, now: now, calendar: calendar).map { (start: $0.day, total: $0.total) }
            return ActivityBars(byMonth: false, points: points)
        }
        switch period {
        case .today, .week: return daily(7)
        case .month: return daily(30)
        case .all:
            let span = dayCount(totals, .all, now: now, calendar: calendar)
            if span <= 60 { return daily(max(span, 7)) }
            var months: [Date: ActivityTotal] = [:]
            for (key, value) in totals {
                guard let d = date(fromKey: key, calendar: calendar),
                      let m = calendar.dateInterval(of: .month, for: d)?.start else { continue }
                months[m, default: ActivityTotal()] = months[m, default: ActivityTotal()] + value
            }
            guard let first = months.keys.min() else { return ActivityBars(byMonth: true, points: []) }
            var points: [(start: Date, total: ActivityTotal)] = []
            var cursor = first
            while cursor <= now {
                points.append((cursor, months[cursor] ?? ActivityTotal()))
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
            return ActivityBars(byMonth: true, points: points)
        }
    }

    private static func firstDay(_ totals: [String: ActivityTotal], calendar: Calendar) -> Date? {
        totals.keys.min().flatMap { date(fromKey: $0, calendar: calendar) }
    }

    private static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    // MARK: Token detail

    public static func encodeDetail(_ entries: [TokenDetailEntry]) -> Data {
        (try? JSONEncoder().encode(entries.sorted { ($0.tool, $0.model) < ($1.tool, $1.model) })) ?? Data()
    }

    /// Tool + model totals for a period: the largest per (Mac, day, tool,
    /// model) — the same snapshot rule as `tokens` — summed across the rest.
    /// Pass `deviceKey` to restrict to one Mac.
    public static func tokenDetail(_ records: [ActivityRecord], _ period: ActivityPeriod, deviceKey: String? = nil,
                                   now: Date = Date(), calendar: Calendar = .current) -> [TokenDetailEntry] {
        let cutoff = cutoffKey(period, now: now, calendar: calendar)
        let decoder = JSONDecoder()
        struct Key: Hashable { let device, day, tool, model: String }
        var best: [Key: TokenDetailEntry] = [:]
        for r in records where !r.tokenDetail.isEmpty
            && (deviceKey == nil || r.deviceKey == deviceKey) && (cutoff.map { r.day >= $0 } ?? true) {
            guard let entries = try? decoder.decode([TokenDetailEntry].self, from: r.tokenDetail) else { continue }
            for e in entries {
                let k = Key(device: r.deviceKey, day: r.day, tool: e.tool, model: e.model)
                var v = best[k] ?? TokenDetailEntry(tool: e.tool, model: e.model, tokens: 0, cost: 0, calls: 0)
                v.tokens = max(v.tokens, e.tokens); v.cost = max(v.cost, e.cost); v.calls = max(v.calls, e.calls)
                best[k] = v
            }
        }
        var merged: [String: TokenDetailEntry] = [:]
        for (k, v) in best {
            let key = k.tool + "|" + k.model
            var m = merged[key] ?? TokenDetailEntry(tool: k.tool, model: k.model, tokens: 0, cost: 0, calls: 0)
            m.tokens += v.tokens; m.cost += v.cost; m.calls += v.calls
            merged[key] = m
        }
        return merged.values.sorted { $0.tokens > $1.tokens }
    }

    /// The Macs that have reported, most recently named first.
    public static func devices(_ records: [ActivityRecord]) -> [(key: String, name: String)] {
        var seen: [String: String] = [:]
        var order: [String] = []
        for r in records.sorted(by: { $0.dayStart > $1.dayStart }) where seen[r.deviceKey] == nil {
            seen[r.deviceKey] = r.deviceName
            order.append(r.deviceKey)
        }
        return order.map { ($0, seen[$0] ?? "") }
    }
}
