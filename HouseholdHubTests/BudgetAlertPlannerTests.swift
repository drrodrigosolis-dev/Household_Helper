import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 23 F7: budget alerts at 80 % and 100 %, once per category per month, names only.
struct BudgetAlertPlannerTests {
    private static let dining = UUID(uuidString: "00000000-0000-0000-0000-00000000D1D1")!
    private let september = BudgetMonth(year: 2026, month: 9)
    private let october = BudgetMonth(year: 2026, month: 10)

    private static func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func source(spent: Int64, available: Int64 = 50_000) -> BudgetAlertSource {
        BudgetAlertSource(
            categoryID: Self.dining, categoryName: "Dining", spent: Self.cad(spent), available: Self.cad(available))
    }

    private func key(_ month: BudgetMonth, _ threshold: BudgetAlertThreshold) -> String {
        BudgetAlertPlanner.key(month: month, categoryID: Self.dining, threshold: threshold)
    }

    // MARK: Thresholds

    @Test(arguments: [
        (0 as Int64, 50_000 as Int64, nil as BudgetAlertThreshold?),
        (39_999, 50_000, nil),
        (40_000, 50_000, .eighty),  // exactly 80 %
        (49_999, 50_000, .eighty),
        (50_000, 50_000, .hundred),  // exactly the budget
        (70_000, 50_000, .hundred),
        (1, 0, .hundred),  // nothing available: any spending is over
        (1, -2_000, .hundred),  // behind after a rolled-over overspend
        (0, -2_000, nil),  // behind, but nothing spent this month
    ])
    func thresholdReached(spent: Int64, available: Int64, expected: BudgetAlertThreshold?) {
        #expect(BudgetAlertPlanner.reached(spent: Self.cad(spent), available: Self.cad(available)) == expected)
    }

    // MARK: Plans

    @Test func crossingEightySendsOneAlert() {
        let plan = BudgetAlertPlanner().plan([source(spent: 41_000)], month: september, alreadySent: [])
        #expect(plan.alerts.map(\.threshold) == [.eighty])
        #expect(plan.alerts.first?.id == key(september, .eighty))
        #expect(plan.alerts.first?.categoryName == "Dining")
        #expect(plan.sentKeys == [key(september, .eighty)])
    }

    @Test func crossingHundredAfterEightySendsTheSecondAlert() {
        let sent: Set = [key(september, .eighty)]
        let plan = BudgetAlertPlanner().plan([source(spent: 52_000)], month: september, alreadySent: sent)
        #expect(plan.alerts.map(\.threshold) == [.hundred])
        #expect(Set(plan.sentKeys) == [key(september, .eighty), key(september, .hundred)])
    }

    @Test func crossingBothAtOnceSendsOnlyTheHundredAndMarksBoth() {
        let plan = BudgetAlertPlanner().plan([source(spent: 60_000)], month: september, alreadySent: [])
        #expect(plan.alerts.map(\.threshold) == [.hundred])
        #expect(Set(plan.sentKeys) == [key(september, .eighty), key(september, .hundred)])
    }

    @Test func alreadySentThisMonthSendsNothing() {
        let sent: Set = [key(september, .eighty), key(september, .hundred)]
        let plan = BudgetAlertPlanner().plan([source(spent: 60_000)], month: september, alreadySent: sent)
        #expect(plan.alerts.isEmpty)
        #expect(Set(plan.sentKeys) == sent)
    }

    @Test func aNewMonthStartsAfreshAndForgetsLastMonth() {
        let sent: Set = [key(september, .eighty), key(september, .hundred)]
        let plan = BudgetAlertPlanner().plan([source(spent: 42_000)], month: october, alreadySent: sent)
        #expect(plan.alerts.map(\.id) == [key(october, .eighty)])
        #expect(plan.sentKeys == [key(october, .eighty)], "Last month's keys are dropped")
    }

    @Test func aRefundBringingSpendingBackUnderSendsNothingAndCrossingAgainDoesNotRepeat() {
        let planner = BudgetAlertPlanner()
        let first = planner.plan([source(spent: 41_000)], month: september, alreadySent: [])
        #expect(first.alerts.count == 1)
        // A refund takes spending back under 80 %.
        let refunded = planner.plan([source(spent: 30_000)], month: september, alreadySent: Set(first.sentKeys))
        #expect(refunded.alerts.isEmpty)
        #expect(refunded.sentKeys == first.sentKeys, "The alert stays sent for the month")
        // Spending again past 80 % the same month does not repeat it.
        let again = planner.plan([source(spent: 45_000)], month: september, alreadySent: Set(refunded.sentKeys))
        #expect(again.alerts.isEmpty)
    }

    @Test func eachCategoryIsPlannedOnItsOwnInNameOrder() {
        let groceries = UUID()
        let sources = [
            source(spent: 45_000),
            BudgetAlertSource(
                categoryID: groceries, categoryName: "Groceries", spent: Self.cad(10), available: Self.cad(10)),
            BudgetAlertSource(
                categoryID: UUID(), categoryName: "Housing", spent: Self.cad(100), available: Self.cad(100_000)),
        ]
        let plan = BudgetAlertPlanner().plan(sources, month: september, alreadySent: [])
        #expect(plan.alerts.map(\.categoryName) == ["Dining", "Groceries"])
        #expect(plan.alerts.map(\.threshold) == [.eighty, .hundred])
        #expect(plan.alerts.last?.categoryID == groceries)
    }

    // MARK: Service

    @Test func theServiceNamesEachBudgetWithItsCategory() async throws {
        let zone = TimeZone(identifier: "America/Vancouver")!
        let calendar = HouseholdCalendar(timeZone: zone)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let all = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
        let dining = try #require(all.first { $0.name == "Dining" }).id
        try await categories.setBudget(
            for: dining, limit: Self.cad(10_000), rollsOver: false, now: now, calendar: calendar)
        let hourAgo = now.addingTimeInterval(-3_600)
        let draft = TransactionDraft(
            amount: Self.cad(8_500), type: .expense, occurredAt: hourAgo, categoryID: dining)
        try await ledger.create(draft, now: now)
        let sources = try await ledger.budgetAlertSources(month: now, calendar: calendar)
        let expected = BudgetAlertSource(
            categoryID: dining, categoryName: "Dining", spent: Self.cad(8_500), available: Self.cad(10_000))
        #expect(sources == [expected])
        let plan = BudgetAlertPlanner().plan(
            sources, month: BudgetMonth(containing: now, calendar: calendar), alreadySent: [])
        #expect(plan.alerts.map(\.threshold) == [.eighty])
    }
}
