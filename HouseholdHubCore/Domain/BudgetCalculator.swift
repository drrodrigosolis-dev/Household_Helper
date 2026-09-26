import Foundation

/// A budget as value data for the math (Sprint 11).
public struct BudgetRule: Hashable, Sendable {
    public var categoryID: UUID
    public var limit: Money
    public var rollsOver: Bool
    /// Start of the first month the budget counts, in the household calendar.
    public var startMonth: Date

    public init(categoryID: UUID, limit: Money, rollsOver: Bool, startMonth: Date) {
        self.categoryID = categoryID
        self.limit = limit
        self.rollsOver = rollsOver
        self.startMonth = startMonth
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

    /// Spent as a share of what is available, for progress bars and ordering; 1 or more once it is all used.
    public var usedFraction: Double {
        guard available.minorUnits > 0 else { return spent.minorUnits > 0 || available.minorUnits < 0 ? 1 : 0 }
        return Double(spent.minorUnits) / Double(available.minorUnits)
    }
}

/// Deterministic budget math (Sprint 11): what a category spent in a month, and what rolled into it. No persistence,
/// no clock.
public struct BudgetCalculator: Sendable {
    public init() {}

    /// - Parameters:
    ///   - lines: expense lines of the budgeted categories, each with its category, from the earliest `startMonth` on.
    ///     Only expenses count; the caller decides whether pending ones are included.
    ///   - month: any date in the month to report.
    public func statuses(
        _ rules: [BudgetRule], lines: [BudgetLine], month: Date, calendar: HouseholdCalendar
    ) throws -> [BudgetStatus] {
        let monthStart = calendar.startOfMonth(for: month)
        return try rules.map { rule in
            let code = rule.limit.currencyCode
            let own = lines.filter { $0.categoryID == rule.categoryID }
            let spent = try spending(own, in: monthStart, calendar: calendar, currencyCode: code)
            var carried = Money.zero(code)
            if rule.rollsOver {
                // Every whole month from the budget's first month up to the one reported: limit minus spending,
                // both ways (a leftover adds, an overspend takes).
                var cursor = calendar.startOfMonth(for: rule.startMonth)
                while cursor < monthStart {
                    let used = try spending(own, in: cursor, calendar: calendar, currencyCode: code)
                    carried = try carried.adding(rule.limit.subtracting(used))
                    guard let next = calendar.calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                    cursor = next
                }
            }
            let available = try rule.limit.adding(carried)
            return BudgetStatus(
                categoryID: rule.categoryID, limit: rule.limit, carriedIn: carried, available: available,
                spent: spent, remaining: try available.subtracting(spent))
        }
    }

    private func spending(
        _ lines: [BudgetLine], in monthStart: Date, calendar: HouseholdCalendar, currencyCode: String
    ) throws -> Money {
        let end = calendar.calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
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
