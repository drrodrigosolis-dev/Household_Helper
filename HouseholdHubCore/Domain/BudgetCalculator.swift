import Foundation

/// A calendar month as numbers (Sprint 11): independent of time zone, turned into instants only through
/// `HouseholdCalendar`.
public struct BudgetMonth: Hashable, Sendable, Comparable {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month containing `date` in the household calendar.
    public init(containing date: Date, calendar: HouseholdCalendar) {
        let parts = calendar.calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    /// The first instant of the month in the household calendar.
    public func start(in calendar: HouseholdCalendar) -> Date {
        let components = DateComponents(year: year, month: month, day: 1, hour: 12)
        let noon = calendar.calendar.date(from: components) ?? .distantPast
        return calendar.startOfMonth(for: noon)
    }

    public static func < (lhs: BudgetMonth, rhs: BudgetMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// A budget as value data for the math (Sprint 11).
public struct BudgetRule: Hashable, Sendable {
    public var categoryID: UUID
    public var limit: Money
    public var rollsOver: Bool
    /// The first month the budget counts.
    public var start: BudgetMonth

    public init(categoryID: UUID, limit: Money, rollsOver: Bool, start: BudgetMonth) {
        self.categoryID = categoryID
        self.limit = limit
        self.rollsOver = rollsOver
        self.start = start
    }
}

/// One budget's figures for one month. `available` is the limit plus what rolled over (negative after an overspend);
/// `remaining` is what is left of it, negative when over.
public struct BudgetStatus: Equatable, Sendable {
    public let categoryID: UUID
    public let limit: Money
    public let carriedIn: Money
    public let available: Money
    public let spent: Money
    public let remaining: Money

    public var isOver: Bool { remaining.minorUnits < 0 }

    /// Spent as a share of what is available, for progress bars and ordering only (a ratio, never money); 1 once
    /// nothing is available and something was spent or the budget is already behind.
    public var usedFraction: Double {
        guard available.minorUnits > 0 else { return spent.minorUnits > 0 || available.minorUnits < 0 ? 1 : 0 }
        return Double(spent.minorUnits) / Double(available.minorUnits)
    }
}

/// Deterministic budget math (Sprint 11): what a category spent in a month, and what rolled into it. No persistence,
/// no clock. Months are stepped with `HouseholdCalendar` (exclusive month ends), so a month that starts after
/// midnight because of a DST change still meets the next one exactly.
public struct BudgetCalculator: Sendable {
    public init() {}

    /// - Parameters:
    ///   - lines: expense lines of the budgeted categories, each with its category, from the earliest start on. Only
    ///     expenses count; the caller decides whether pending ones are included.
    ///   - month: any date in the month to report.
    public func statuses(
        _ rules: [BudgetRule], lines: [BudgetLine], month: Date, calendar: HouseholdCalendar
    ) throws -> [BudgetStatus] {
        let monthStart = calendar.startOfMonth(for: month)
        return try rules.map { rule in
            let code = rule.limit.currencyCode
            let own = lines.filter { $0.categoryID == rule.categoryID }
            let spent = try spending(own, from: monthStart, calendar: calendar, currencyCode: code)
            var carried = Money.zero(code)
            if rule.rollsOver {
                // Every whole month from the budget's first month up to the one reported: limit minus spending,
                // both ways (a leftover adds, an overspend takes).
                var cursor = rule.start.start(in: calendar)
                while cursor < monthStart {
                    let used = try spending(own, from: cursor, calendar: calendar, currencyCode: code)
                    carried = try carried.adding(rule.limit.subtracting(used))
                    cursor = calendar.endOfMonth(for: cursor)
                }
            }
            let available = try rule.limit.adding(carried)
            return BudgetStatus(
                categoryID: rule.categoryID, limit: rule.limit, carriedIn: carried, available: available,
                spent: spent, remaining: try available.subtracting(spent))
        }
    }

    private func spending(
        _ lines: [BudgetLine], from monthStart: Date, calendar: HouseholdCalendar, currencyCode: String
    ) throws -> Money {
        let end = calendar.endOfMonth(for: monthStart)
        let inMonth = lines.filter { $0.occurredAt >= monthStart && $0.occurredAt < end }
        return try Money.sum(inMonth.map(\.amount), currencyCode: currencyCode)
    }
}

/// An expense counted against a budget: positive magnitude, its category, and when it happened.
public struct BudgetLine: Hashable, Sendable {
    public var categoryID: UUID
    public var amount: Money
    public var occurredAt: Date

    public init(categoryID: UUID, amount: Money, occurredAt: Date) {
        self.categoryID = categoryID
        self.amount = amount
        self.occurredAt = occurredAt
    }
}
