import Foundation

/// The month-end summary on Analytics (Sprint 23, F5): one calendar month's income against spending, its spending
/// against the budgets it had, its top categories, and where each savings goal stands. Built from the Analytics
/// report, the budget report and the goals report of the same household, so every figure matches those screens.
public struct MonthSummary: Equatable, Sendable {
    public let interval: DateInterval
    public let income: Money
    /// Spending after refunds, as Analytics shows it.
    public let expense: Money
    public let refunds: Money
    /// Income minus spending after refunds.
    public let net: Money
    /// What the month's budgets had available (each limit plus what rolled into it), added up, as Budgets shows it;
    /// nil when no budget counted in that month.
    public let budgetTotal: Money?
    /// What the budgeted categories spent in the month, each as Budgets shows it (never below zero).
    public let budgetSpent: Money
    /// Budgets whose month ended over what was available (the limit plus rollover).
    public let overBudgetCount: Int
    /// The month's largest spending categories, largest first.
    public let topCategories: [CategorySpend]
    /// Goals that aren't archived, in list order. Goals have no monthly history, so these are today's figures.
    public let goals: [GoalStatus]

    public static let topCategoryCount = 3

    public var goalsReached: Int { goals.filter(\.isReached).count }

    /// Anything was earned, spent or given back in the month.
    public var hasActivity: Bool { !income.isZero || !expense.isZero || !refunds.isZero }

    /// Budgeted spending went past what the budgets had available, added up.
    public var isOverBudgetTotal: Bool {
        guard let budgetTotal else { return false }
        return budgetSpent.minorUnits > budgetTotal.minorUnits
    }

    /// - Parameters:
    ///   - report: the Analytics report for the month.
    ///   - budgets: the budget report for the same month.
    ///   - goals: the goals report (archived goals are left out here).
    public init(report: AnalyticsReport, budgets: [BudgetStatus], goals: [GoalStatus]) throws {
        let code = report.income.currencyCode
        interval = report.interval
        income = report.income
        expense = report.expense
        refunds = report.refunds
        net = report.net
        budgetTotal = try budgets.isEmpty ? nil : Money.sum(budgets.map(\.available), currencyCode: code)
        budgetSpent = try Money.sum(budgets.map(\.spent), currencyCode: code)
        overBudgetCount = budgets.filter(\.isOver).count
        topCategories = Array(report.byCategory.prefix(Self.topCategoryCount))
        self.goals = goals.filter { !$0.rule.isArchived }
    }
}
