import Foundation

/// How often a detected pattern repeats (Sprint 23 F2).
public enum RecurringCadence: String, CaseIterable, Sendable {
    case weekly
    case biweekly
    case monthly

    /// Days between two occurrences that still count as this cadence.
    var gapDays: ClosedRange<Int> {
        switch self {
        case .weekly: return 6...8
        case .biweekly: return 13...15
        case .monthly: return 27...33
        }
    }

    /// Nominal length of one period in days, for "still going" (the last one is within 1.5 periods of today).
    var periodDays: Int {
        switch self {
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly: return 30
        }
    }
}

/// One past transaction as the detector sees it (Sprint 23 F2). Built by the service from the store, or by tests.
public struct RecurringHistoryItem: Equatable, Sendable {
    public var id: UUID
    /// Positive magnitude; `type` gives the sign.
    public var amount: Money
    public var type: TransactionType
    public var status: TransactionStatus
    public var occurredAt: Date
    public var merchantID: UUID?
    /// The merchant's name: its current display name when `merchantID` is set, else the record's snapshot.
    public var merchantName: String?
    public var notes: String?
    public var categoryID: UUID?
    public var accountID: UUID?
    /// Set when the transaction was posted from a series: it is already recurring.
    public var recurringSeriesID: UUID?

    public init(
        id: UUID = UUID(), amount: Money, type: TransactionType, status: TransactionStatus = .posted,
        occurredAt: Date, merchantID: UUID? = nil, merchantName: String? = nil, notes: String? = nil,
        categoryID: UUID? = nil, accountID: UUID? = nil, recurringSeriesID: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.status = status
        self.occurredAt = occurredAt
        self.merchantID = merchantID
        self.merchantName = merchantName
        self.notes = notes
        self.categoryID = categoryID
        self.accountID = accountID
        self.recurringSeriesID = recurringSeriesID
    }
}

/// What an existing series is about, so a pattern it already covers is not suggested again.
public struct ExistingSeriesKey: Equatable, Sendable {
    public var type: TransactionType
    public var merchantID: UUID?
    /// The series' name and its store's name, in any form (they are normalized for the comparison).
    public var names: [String]

    public init(type: TransactionType, merchantID: UUID? = nil, names: [String] = []) {
        self.type = type
        self.merchantID = merchantID
        self.names = names
    }
}

/// A repeating pattern found in the history, offered as "Make it a bill?" (Sprint 23 F2). A draft only: nothing is
/// created until the person adds it through the recurring editor.
public struct RecurringSuggestion: Hashable, Sendable, Identifiable {
    /// Stable per merchant and type ("expense|id:<uuid>", "income|name:acme payroll"): what a dismissal remembers.
    public let id: String
    public let merchantName: String
    public let merchantID: UUID?
    public let type: TransactionType
    /// A purchase for weekly or every-two-weeks spending at a store, else a bill.
    public let kind: RecurringKind
    /// The most recent amount.
    public let amount: Money
    public let cadence: RecurringCadence
    public let rule: RecurrenceRule
    /// The first occurrence of `rule` on or after the start of today (a local midnight).
    public let nextDate: Date
    /// How many transactions in a row follow the pattern, the most recent included.
    public let occurrenceCount: Int
    public let lastDate: Date
    /// The most recent transaction's category and account, to prefill the editor.
    public let categoryID: UUID?
    public let accountID: UUID?

    public init(
        id: String, merchantName: String, merchantID: UUID?, type: TransactionType, kind: RecurringKind,
        amount: Money, cadence: RecurringCadence, rule: RecurrenceRule, nextDate: Date, occurrenceCount: Int,
        lastDate: Date, categoryID: UUID?, accountID: UUID?
    ) {
        self.id = id
        self.merchantName = merchantName
        self.merchantID = merchantID
        self.type = type
        self.kind = kind
        self.amount = amount
        self.cadence = cadence
        self.rule = rule
        self.nextDate = nextDate
        self.occurrenceCount = occurrenceCount
        self.lastDate = lastDate
        self.categoryID = categoryID
        self.accountID = accountID
    }
}

/// Finds recurring spending and income in posted history (Sprint 23 F2). Pure and deterministic: no clock, no store.
///
/// Posted expenses and income that no series posted are grouped by merchant (its id, else its normalized name or the
/// notes) and type. A group is suggested when its most recent transactions, walking back from the latest, repeat
/// weekly (6–8 days apart), every two weeks (13–15) or monthly (27–33 days, on the same day of the month ±3) at
/// least three times in a row, each amount within ±10 % of the latest; the latest is at most 1.5 periods before
/// today; and no series (of the same type) already names that merchant.
public struct RecurringDetector: Sendable {
    public static let minimumOccurrences = 3
    /// Largest distance between two days of the month that still counts as "the same day".
    static let dayOfMonthTolerance = 3

    public init() {}

    public func suggestions(
        from history: [RecurringHistoryItem], existing: [ExistingSeriesKey], now: Date, calendar: HouseholdCalendar
    ) -> [RecurringSuggestion] {
        var groups: [String: [RecurringHistoryItem]] = [:]
        for item in history where Self.isCandidate(item) {
            guard let key = Self.merchantKey(item) else { continue }
            groups["\(item.type.rawValue)|\(key)", default: []].append(item)
        }
        var found: [RecurringSuggestion] = []
        for (id, items) in groups {
            let ordered = items.sorted { ($0.occurredAt, $0.id.uuidString) < ($1.occurredAt, $1.id.uuidString) }
            guard let latest = ordered.last, !Self.isCovered(latest, by: existing) else { continue }
            if let suggestion = detect(id: id, ordered: ordered, now: now, calendar: calendar) {
                found.append(suggestion)
            }
        }
        return found.sorted { ($0.nextDate, $0.id) < ($1.nextDate, $1.id) }
    }

    // MARK: Grouping

    static func isCandidate(_ item: RecurringHistoryItem) -> Bool {
        item.status == .posted && (item.type == .expense || item.type == .income) && item.recurringSeriesID == nil
            && item.amount.minorUnits > 0
    }

    /// The merchant's id, else its normalized name, else the normalized notes; nil when there is nothing to go by.
    static func merchantKey(_ item: RecurringHistoryItem) -> String? {
        if let id = item.merchantID {
            return "id:" + id.uuidString
        }
        for text in [item.merchantName, item.notes] {
            let normalized = Merchant.normalize(text ?? "")
            if !normalized.isEmpty {
                return "name:" + normalized
            }
        }
        return nil
    }

    static func isCovered(_ item: RecurringHistoryItem, by existing: [ExistingSeriesKey]) -> Bool {
        let itemNames = Set([item.merchantName, item.notes].compactMap { $0 }.map(Merchant.normalize))
            .subtracting([""])
        return existing.contains { series in
            guard series.type == item.type else { return false }
            if let id = series.merchantID, id == item.merchantID {
                return true
            }
            return series.names.contains { itemNames.contains(Merchant.normalize($0)) }
        }
    }

    // MARK: Detection

    private func detect(
        id: String, ordered: [RecurringHistoryItem], now: Date, calendar: HouseholdCalendar
    ) -> RecurringSuggestion? {
        guard let latest = ordered.last else { return nil }
        for cadence in RecurringCadence.allCases {
            let count = runLength(ordered, cadence: cadence, calendar: calendar)
            guard count >= Self.minimumOccurrences else { continue }
            let sinceLatest = calendar.dayDifference(from: latest.occurredAt, to: now)
            guard sinceLatest <= cadence.periodDays * 3 / 2 else { return nil }
            let rule = Self.rule(for: cadence, latest: latest.occurredAt, calendar: calendar)
            let anchor = calendar.startOfDay(for: latest.occurredAt)
            let today = calendar.startOfDay(for: now)
            // `nextOccurrence(after:)` is strict: step back one second so today itself can be the next date.
            let after = max(anchor, today.addingTimeInterval(-1))
            let engine = RecurrenceEngine()
            guard let next = engine.nextOccurrence(of: rule, start: anchor, after: after, calendar: calendar) else {
                return nil
            }
            let name = [latest.merchantName, latest.notes]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            let kind: RecurringKind = cadence != .monthly && latest.type == .expense ? .purchase : .bill
            return RecurringSuggestion(
                id: id, merchantName: name ?? "", merchantID: latest.merchantID, type: latest.type, kind: kind,
                amount: latest.amount, cadence: cadence, rule: rule, nextDate: next, occurrenceCount: count,
                lastDate: latest.occurredAt, categoryID: latest.categoryID, accountID: latest.accountID)
        }
        return nil
    }

    /// How many transactions, walking back from the latest, follow `cadence` one after another.
    private func runLength(
        _ ordered: [RecurringHistoryItem], cadence: RecurringCadence, calendar: HouseholdCalendar
    ) -> Int {
        guard let latest = ordered.last else { return 0 }
        let templateDay = calendar.calendar.component(.day, from: latest.occurredAt)
        var count = 1
        var later = latest
        for earlier in ordered.dropLast().reversed() {
            let gap = calendar.dayDifference(from: earlier.occurredAt, to: later.occurredAt)
            guard cadence.gapDays.contains(gap), Self.isClose(earlier.amount, to: latest.amount) else { break }
            if cadence == .monthly {
                let day = calendar.calendar.component(.day, from: earlier.occurredAt)
                guard Self.dayDistance(day, templateDay) <= Self.dayOfMonthTolerance else { break }
            }
            count += 1
            later = earlier
        }
        return count
    }

    /// Within ±10 % of the template, in integer minor units.
    static func isClose(_ amount: Money, to template: Money) -> Bool {
        guard amount.currencyCode == template.currencyCode, template.minorUnits > 0, amount.minorUnits > 0 else {
            return false
        }
        // Both are positive, so the difference cannot overflow.
        let difference = abs(amount.minorUnits - template.minorUnits)
        let (scaled, overflow) = difference.multipliedReportingOverflow(by: 10)
        return !overflow && scaled <= template.minorUnits
    }

    /// Distance between two days of the month, wrapping at the month's end (the 30th and the 1st are 2 apart).
    static func dayDistance(_ first: Int, _ second: Int) -> Int {
        let direct = abs(first - second)
        return min(direct, 31 - direct)
    }

    static func rule(for cadence: RecurringCadence, latest: Date, calendar: HouseholdCalendar) -> RecurrenceRule {
        let weekday = calendar.calendar.component(.weekday, from: latest)
        switch cadence {
        case .weekly: return .weekly(interval: 1, weekday: weekday)
        case .biweekly: return .weekly(interval: 2, weekday: weekday)
        case .monthly: return .monthlyOnDay(day: calendar.calendar.component(.day, from: latest))
        }
    }
}

/// The suggestions a person dismissed (Sprint 23 F2), by merchant and type. A device preference kept in
/// UserDefaults by the app, never in SwiftData or a backup.
public struct RecurringSuggestionDismissals: Equatable, Sendable {
    public private(set) var keys: Set<String>

    public init(_ keys: [String] = []) {
        self.keys = Set(keys)
    }

    public func visible(_ suggestions: [RecurringSuggestion]) -> [RecurringSuggestion] {
        suggestions.filter { !keys.contains($0.id) }
    }

    public mutating func dismiss(_ suggestion: RecurringSuggestion) {
        keys.insert(suggestion.id)
    }

    /// Sorted, for storing.
    public var stored: [String] { keys.sorted() }
}
