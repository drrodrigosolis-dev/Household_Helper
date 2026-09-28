import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 23: budget month history (A-017), category change vs last month (A-018) and the month-end summary (F5).
struct Sprint23AnalyticsTests {
    private static let calendar = HouseholdCalendar(
        timeZone: TimeZone(identifier: "America/Vancouver")!, firstWeekday: 2)
    private let calendar = Sprint23AnalyticsTests.calendar
    /// Thursday 2026-10-15, noon in Vancouver.
    private let now: Date = Sprint23AnalyticsTests.date(2026, 10, 15)

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func cad(_ minorUnits: Int64) -> Money { Money(minorUnits: minorUnits, currencyCode: "CAD") }

    // MARK: Month stepping (A-017)

    static let monthSteps: [(Int, Int, Int, Int, Int)] = [
        (2026, 9, -1, 2026, 8),
        (2026, 1, -1, 2025, 12),
        (2026, 12, 1, 2027, 1),
        (2026, 9, -21, 2024, 12),
        (2026, 3, 0, 2026, 3),
        (2025, 11, 14, 2027, 1),
    ]

    @Test(arguments: monthSteps)
    func monthsStepAcrossYears(year: Int, month: Int, count: Int, expectedYear: Int, expectedMonth: Int) {
        let stepped = BudgetMonth(year: year, month: month).adding(months: count)
        #expect(stepped == BudgetMonth(year: expectedYear, month: expectedMonth))
    }

    @Test func navigationGoesBackAYearAndNeverPastTheCurrentMonth() {
        let navigator = BudgetMonthNavigator(
            now: now, calendar: calendar,
            starts: [BudgetMonth(year: 2026, month: 8), BudgetMonth(year: 2026, month: 7)])
        let october = BudgetMonth(year: 2026, month: 10)
        let yearBack = BudgetMonth(year: 2025, month: 10)
        #expect(navigator.current == october)
        #expect(navigator.earliest == yearBack)
        #expect(!navigator.canGoForward(from: october), "Never past the current month")
        #expect(navigator.next(of: october) == october)
        #expect(navigator.canGoBack(from: october))
        #expect(navigator.previous(of: october) == BudgetMonth(year: 2026, month: 9))
        #expect(navigator.canGoForward(from: BudgetMonth(year: 2026, month: 9)))
        #expect(!navigator.canGoBack(from: yearBack))
        #expect(navigator.previous(of: yearBack) == yearBack)
        #expect(navigator.clamped(BudgetMonth(year: 2027, month: 2)) == october)
        #expect(navigator.clamped(BudgetMonth(year: 2020, month: 2)) == yearBack)

        let empty = BudgetMonthNavigator(now: now, calendar: calendar, starts: [])
        #expect(empty.earliest == yearBack)
    }

    @Test func anOlderBudgetOpensItsWholeRolloverHistory() {
        let march = BudgetMonth(year: 2025, month: 3)
        let navigator = BudgetMonthNavigator(
            now: now, calendar: calendar, starts: [BudgetMonth(year: 2026, month: 9), march])
        #expect(navigator.earliest == march)
        #expect(!navigator.canGoBack(from: march))
    }

    // MARK: Budget history through the service (A-017)

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let categories: CategoryService
        let groceries: UUID
        let dining: UUID
    }

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.completeOnboarding(
            currencyCode: "CAD", startingBalance: cad(500_000), asOf: Self.date(2026, 6, 1), now: now)
        let groceries = try await categories.create(
            name: "Food", icon: "cart", color: .black, kind: .expense, now: now)
        let dining = try await categories.create(
            name: "Eating out", icon: "fork.knife", color: .black, kind: .expense, now: now)
        return Fixture(
            container: container, ledger: ledger, categories: categories, groceries: groceries, dining: dining)
    }

    @discardableResult
    private func spend(
        _ minorUnits: Int64, on date: Date, in category: UUID?, status: TransactionStatus = .posted,
        fixture: Fixture
    ) async throws -> UUID {
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(minorUnits), type: .expense, occurredAt: date, status: status, categoryID: category),
            now: now)
    }

    private func status(_ month: Date, _ fixture: Fixture) async throws -> BudgetStatus? {
        try await fixture.ledger.budgetReport(month: month, calendar: calendar)
            .first { $0.categoryID == fixture.groceries }
    }

    struct HistoryCase: Sendable, CustomTestStringConvertible {
        let label: String
        let month: Int
        let carried: Int64
        let spent: Int64
        let remaining: Int64
        var testDescription: String { label }
    }

    /// A 300.00 rolled-over budget set on July 1; 50.00 spent in June, 200.00 in July, 400.00 in August, 100.00 in
    /// September.
    static let historyCases = [
        HistoryCase(label: "June: before its start", month: 6, carried: 0, spent: 5_000, remaining: 25_000),
        HistoryCase(label: "July: first month", month: 7, carried: 0, spent: 20_000, remaining: 10_000),
        HistoryCase(label: "August: July's leftover", month: 8, carried: 10_000, spent: 40_000, remaining: 0),
        HistoryCase(label: "September: August used it up", month: 9, carried: 0, spent: 10_000, remaining: 20_000),
        HistoryCase(label: "October: no spending yet", month: 10, carried: 20_000, spent: 0, remaining: 50_000),
    ]

    @Test(arguments: historyCases)
    func pastMonthsShowTheirSpendingAndTheRolloverBuiltUpToThem(_ entry: HistoryCase) async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.setBudget(
            for: fixture.groceries, limit: cad(30_000), rollsOver: true, now: Self.date(2026, 7, 1),
            calendar: calendar)
        // Spending before the start month shows in its own month but never rolls over.
        try await spend(5_000, on: Self.date(2026, 6, 20), in: fixture.groceries, fixture: fixture)
        try await spend(20_000, on: Self.date(2026, 7, 12), in: fixture.groceries, fixture: fixture)
        try await spend(25_000, on: Self.date(2026, 8, 3), in: fixture.groceries, fixture: fixture)
        try await spend(15_000, on: Self.date(2026, 8, 31, hour: 23), in: fixture.groceries, fixture: fixture)
        try await spend(10_000, on: Self.date(2026, 9, 1, hour: 0), in: fixture.groceries, fixture: fixture)
        // Other categories and cancelled spending never count.
        try await spend(9_000, on: Self.date(2026, 8, 3), in: fixture.dining, fixture: fixture)
        try await spend(9_000, on: Self.date(2026, 8, 3), in: fixture.groceries, status: .cancelled, fixture: fixture)

        let row = try #require(try await status(Self.date(2026, entry.month, 15), fixture))
        #expect(row.limit == cad(30_000))
        #expect(row.carriedIn == cad(entry.carried))
        #expect(row.spent == cad(entry.spent))
        #expect(row.remaining == cad(entry.remaining))
    }

    @Test func aPastMonthWhoseRefundsExceedItsSpendingShowsNothingSpentButRollsOverTheNet() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.setBudget(
            for: fixture.groceries, limit: cad(5_000), rollsOver: true, now: Self.date(2026, 8, 1), calendar: calendar)
        let august = try await spend(10_000, on: Self.date(2026, 8, 10), in: fixture.groceries, fixture: fixture)
        try await spend(2_000, on: Self.date(2026, 9, 2), in: fixture.groceries, fixture: fixture)
        _ = try await fixture.ledger.refundTransaction(
            august, amount: cad(10_000), occurredAt: Self.date(2026, 9, 5), notes: nil, calendar: calendar, now: now)

        let inAugust = try #require(try await status(Self.date(2026, 8, 20), fixture))
        #expect(inAugust.spent == cad(10_000), "August keeps what it spent")
        #expect(inAugust.isOver)
        let inSeptember = try #require(try await status(Self.date(2026, 9, 20), fixture))
        #expect(inSeptember.carriedIn == cad(-5_000))
        #expect(inSeptember.spent == cad(0), "20.00 spent, 100.00 back: never below zero")
        let inOctober = try #require(try await status(Self.date(2026, 10, 1), fixture))
        // August: 50 - 100 = -50. September: 50 - (20 - 100) = +130. Into October: +80.
        #expect(inOctober.carriedIn == cad(8_000))
    }

    @Test func turningRolloverBackOnKeepsEarlierMonthsSpending() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.setBudget(
            for: fixture.groceries, limit: cad(30_000), rollsOver: true, now: Self.date(2026, 7, 1),
            calendar: calendar)
        try await spend(20_000, on: Self.date(2026, 7, 12), in: fixture.groceries, fixture: fixture)
        try await fixture.categories.setBudget(
            for: fixture.groceries, limit: cad(30_000), rollsOver: false, now: now, calendar: calendar)
        try await fixture.categories.setBudget(
            for: fixture.groceries, limit: cad(30_000), rollsOver: true, now: now, calendar: calendar)
        let july = try #require(try await status(Self.date(2026, 7, 20), fixture))
        #expect(july.spent == cad(20_000))
        #expect(july.carriedIn == cad(0))
        let october = try #require(try await status(now, fixture))
        #expect(october.carriedIn == cad(0), "Counting starts again this month")
    }

    // MARK: Change vs last month (A-018)

    static let changeCases: [(Int64, Int64, CategoryChange.Direction, Int64)] = [
        (12_000, 10_000, .up, 2_000),
        (4_000, 10_000, .down, 6_000),
        (5_000, 5_000, .same, 0),
        (2_500, 0, .up, 2_500),
    ]

    @Test(arguments: changeCases)
    func aChangeSaysWhichWayAndByHowMuch(
        current: Int64, previous: Int64, direction: CategoryChange.Direction, difference: Int64
    ) throws {
        let change = try CategoryChange(categoryID: UUID(), current: cad(current), previous: cad(previous))
        #expect(change.direction == direction)
        #expect(change.difference == cad(difference))
        #expect(!change.difference.isNegative)
    }

    static let comparisonCases: [(AnalyticsPeriod, Int, Int, Int, Int)] = [
        (.thisMonth, 2026, 9, 2026, 10),
        (.lastMonth, 2026, 8, 2026, 9),
    ]

    @Test(arguments: comparisonCases)
    func singleMonthPeriodsCompareWithTheMonthBefore(
        period: AnalyticsPeriod, fromYear: Int, fromMonth: Int, toYear: Int, toMonth: Int
    ) throws {
        let interval = try #require(period.comparisonInterval(now: now, calendar: calendar))
        #expect(interval.start == Self.date(fromYear, fromMonth, 1, hour: 0))
        #expect(interval.end == Self.date(toYear, toMonth, 1, hour: 0))
    }

    @Test(arguments: [AnalyticsPeriod.last3Months, .thisYear, .last12Months])
    func longerPeriodsHaveNoComparison(period: AnalyticsPeriod) {
        #expect(period.comparisonInterval(now: now, calendar: calendar) == nil)
    }

    @Test func januaryComparesWithDecemberOfTheYearBefore() throws {
        let interval = try #require(
            AnalyticsPeriod.thisMonth.comparisonInterval(now: Self.date(2027, 1, 4), calendar: calendar))
        #expect(interval.start == Self.date(2026, 12, 1, hour: 0))
        #expect(interval.end == Self.date(2027, 1, 1, hour: 0))
    }

    @Test func changesFollowTheCurrentOrderAndCountAMissingCategoryAsNothing() throws {
        let food = UUID()
        let fun = UUID()
        func slice(_ id: UUID?, _ units: Int64) -> CategorySpend {
            CategorySpend(categoryID: id, total: cad(units), share: 0)
        }
        let changes = try AnalyticsEngine().changes(
            from: [slice(food, 10_000), slice(nil, 3_000), slice(UUID(), 7_000)],
            to: [slice(fun, 8_000), slice(food, 6_000), slice(nil, 3_000)])
        #expect(changes.map(\.categoryID) == [fun, food, nil])
        #expect(changes.map(\.direction) == [.up, .down, .same])
        #expect(changes.map(\.difference) == [cad(8_000), cad(4_000), cad(0)])
    }

    @Test func theServiceComparesEachCategoryWithTheMonthBeforeAfterRefunds() async throws {
        let fixture = try await makeFixture()
        let september = try await spend(10_000, on: Self.date(2026, 9, 10), in: fixture.groceries, fixture: fixture)
        _ = try await fixture.ledger.refundTransaction(
            september, amount: cad(1_000), occurredAt: Self.date(2026, 9, 12), notes: nil, calendar: calendar,
            now: now)
        try await spend(4_000, on: Self.date(2026, 10, 2), in: fixture.groceries, fixture: fixture)
        try await spend(2_500, on: Self.date(2026, 10, 3), in: fixture.dining, fixture: fixture)
        // Pending spending stays out while Include pending is off.
        try await spend(7_000, on: Self.date(2026, 9, 20), in: fixture.dining, status: .pending, fixture: fixture)

        let service = AnalyticsService.make(container: fixture.container)
        let changes = try await service.categoryChanges(period: .thisMonth, now: now, calendar: calendar)
        let groceries = try #require(changes.first { $0.categoryID == fixture.groceries })
        #expect(groceries.previous == cad(9_000), "September after its refund")
        #expect(groceries.direction == .down)
        #expect(groceries.difference == cad(5_000))
        let dining = try #require(changes.first { $0.categoryID == fixture.dining })
        #expect(dining.direction == .up)
        #expect(dining.difference == cad(2_500))

        try await fixture.ledger.setAnalyticsIncludesPending(true, now: now)
        let withPending = try await service.categoryChanges(period: .thisMonth, now: now, calendar: calendar)
        #expect(withPending.first { $0.categoryID == fixture.dining }?.direction == .down)

        let longer = try await service.categoryChanges(period: .last3Months, now: now, calendar: calendar)
        #expect(longer.isEmpty)
    }

    // MARK: Month-end summary (F5)

    private func report(_ entries: [AnalyticsEntry]) throws -> AnalyticsReport {
        try AnalyticsEngine().report(
            entries, period: .lastMonth, now: now, calendar: calendar, currencyCode: "CAD")
    }

    private func entry(
        _ units: Int64, _ type: TransactionType, _ category: UUID? = nil, day: Int = 10
    ) -> AnalyticsEntry {
        AnalyticsEntry(
            amount: cad(units), type: type, status: .posted, occurredAt: Self.date(2026, 9, day), categoryID: category)
    }

    private func budget(_ category: UUID, limit: Int64, carried: Int64 = 0, spent: Int64) -> BudgetStatus {
        let available = limit + carried
        return BudgetStatus(
            categoryID: category, limit: cad(limit), carriedIn: cad(carried), available: cad(available),
            spent: cad(spent), remaining: cad(available - spent))
    }

    private func goal(saved: Int64, target: Int64, archived: Bool = false) throws -> GoalStatus {
        let rule = GoalRule(
            id: UUID(), name: "Trip", target: cad(target), accountID: UUID(), targetDate: nil, wishlistItemID: nil,
            isArchived: archived)
        return try GoalCalculator().status(of: rule, saved: cad(saved), now: now, calendar: calendar)
    }

    @Test func aMonthWithNoDataSaysSo() throws {
        let summary = try MonthSummary(report: try report([]), budgets: [], goals: [])
        #expect(!summary.hasActivity)
        #expect(summary.budgetTotal == nil)
        #expect(summary.budgetSpent == cad(0))
        #expect(summary.topCategories.isEmpty)
        #expect(summary.goals.isEmpty)
        #expect(!summary.isOverBudgetTotal)
        #expect(summary.interval.start == Self.date(2026, 9, 1, hour: 0))
    }

    @Test func theSummaryAddsUpTheMonth() throws {
        let food = UUID()
        let fun = UUID()
        let rent = UUID()
        let entries = [
            entry(400_000, .income),
            entry(150_000, .expense, rent),
            entry(30_000, .expense, food),
            entry(12_000, .expense, fun),
            entry(2_000, .expense, nil),
            // Outside the month: October, and a transfer.
            AnalyticsEntry(
                amount: cad(99_000), type: .expense, status: .posted, occurredAt: Self.date(2026, 10, 2),
                categoryID: food),
            entry(50_000, .transfer),
        ]
        let budgets = [budget(food, limit: 25_000, spent: 30_000), budget(fun, limit: 20_000, spent: 12_000)]
        let goals = try [
            goal(saved: 50_000, target: 50_000), goal(saved: 10_000, target: 40_000),
            goal(saved: 99_000, target: 1_000, archived: true),
        ]
        let summary = try MonthSummary(report: try report(entries), budgets: budgets, goals: goals)
        #expect(summary.hasActivity)
        #expect(summary.income == cad(400_000))
        #expect(summary.expense == cad(194_000))
        #expect(summary.net == cad(206_000))
        #expect(summary.budgetTotal == cad(45_000))
        #expect(summary.budgetSpent == cad(42_000))
        #expect(!summary.isOverBudgetTotal)
        #expect(summary.overBudgetCount == 1)
        #expect(summary.topCategories.map(\.categoryID) == [rent, food, fun], "The top three, largest first")
        #expect(summary.goals.count == 2, "Archived goals are left out")
        #expect(summary.goalsReached == 1)
    }

    struct RefundCase: Sendable, CustomTestStringConvertible {
        let label: String
        let spent: Int64
        let refunded: Int64
        let expectedExpense: Int64
        let expectedNet: Int64
        var testDescription: String { label }
    }

    static let refundCases = [
        RefundCase(
            label: "a partial refund", spent: 10_000, refunded: 4_000, expectedExpense: 6_000, expectedNet: -6_000),
        RefundCase(
            label: "refunds larger than spending floor at zero", spent: 5_000, refunded: 8_000, expectedExpense: 0,
            expectedNet: 3_000),
    ]

    @Test(arguments: refundCases)
    func refundsLowerTheMonthsSpending(_ entry: RefundCase) throws {
        let food = UUID()
        let entries = [self.entry(entry.spent, .expense, food), self.entry(entry.refunded, .refund, food, day: 20)]
        let summary = try MonthSummary(
            report: try report(entries), budgets: [budget(food, limit: 5_000, spent: entry.expectedExpense)], goals: [])
        #expect(summary.hasActivity)
        #expect(summary.expense == cad(entry.expectedExpense))
        #expect(summary.refunds == cad(entry.refunded))
        #expect(summary.net == cad(entry.expectedNet))
        #expect(summary.isOverBudgetTotal == (entry.expectedExpense > 5_000))
    }

    @Test func theSummaryMatchesTheServicesForLastMonth() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.setBudget(
            for: fixture.groceries, limit: cad(30_000), rollsOver: true, now: Self.date(2026, 8, 1),
            calendar: calendar)
        try await spend(35_000, on: Self.date(2026, 9, 10), in: fixture.groceries, fixture: fixture)
        try await spend(6_000, on: Self.date(2026, 9, 11), in: fixture.dining, fixture: fixture)
        _ = try await fixture.ledger.create(
            TransactionDraft(amount: cad(200_000), type: .income, occurredAt: Self.date(2026, 9, 1)), now: now)

        let lastMonth = AnalyticsPeriod.lastMonth.interval(now: now, calendar: calendar)
        let report = try await AnalyticsService.make(container: fixture.container)
            .report(period: .lastMonth, now: now, calendar: calendar)
        let budgets = try await fixture.ledger.budgetReport(month: lastMonth.start, calendar: calendar)
        let goals = try await fixture.ledger.goalReport(now: now, calendar: calendar)
        let summary = try MonthSummary(report: report, budgets: budgets, goals: goals)
        #expect(summary.expense == cad(41_000))
        #expect(summary.net == cad(159_000))
        #expect(summary.budgetTotal == cad(60_000), "August's 300.00 rolled over, so 600.00 was available")
        #expect(summary.budgetSpent == cad(35_000))
        #expect(summary.overBudgetCount == 0)
        #expect(!summary.isOverBudgetTotal)
        #expect(summary.topCategories.map(\.categoryID) == [fixture.groceries, fixture.dining])
    }
}
