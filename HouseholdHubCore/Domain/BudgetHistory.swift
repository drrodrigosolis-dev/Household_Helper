import Foundation

extension BudgetMonth {
    /// The month `count` months later, or earlier when `count` is negative. Plain calendar numbers, no time zone.
    public func adding(months count: Int) -> BudgetMonth {
        let index = year * 12 + (month - 1) + count
        var (years, months) = index.quotientAndRemainder(dividingBy: 12)
        if months < 0 {
            years -= 1
            months += 12
        }
        return BudgetMonth(year: years, month: months + 1)
    }
}

/// Stepping between months on Budget › Budgets (Sprint 23, A-017): back a year, or further to the oldest budget's
/// start month so its whole rollover can be followed, and forward up to the current month, never past it. Past months
/// are read with each budget's current limit and rollover setting; only spending is historical.
public struct BudgetMonthNavigator: Equatable, Sendable {
    /// How many months before the current one can always be shown.
    public static let historyMonths = 12

    public let current: BudgetMonth
    public let earliest: BudgetMonth

    /// - Parameter starts: each budget's start month.
    public init(now: Date, calendar: HouseholdCalendar, starts: [BudgetMonth]) {
        let current = BudgetMonth(containing: now, calendar: calendar)
        let yearBack = current.adding(months: -Self.historyMonths)
        self.current = current
        self.earliest = min(starts.min() ?? yearBack, yearBack)
    }

    /// `month`, kept inside the months that can be shown.
    public func clamped(_ month: BudgetMonth) -> BudgetMonth {
        min(max(month, earliest), current)
    }

    public func canGoBack(from month: BudgetMonth) -> Bool { month > earliest }

    public func canGoForward(from month: BudgetMonth) -> Bool { month < current }

    public func previous(of month: BudgetMonth) -> BudgetMonth { clamped(month.adding(months: -1)) }

    public func next(of month: BudgetMonth) -> BudgetMonth { clamped(month.adding(months: 1)) }
}
