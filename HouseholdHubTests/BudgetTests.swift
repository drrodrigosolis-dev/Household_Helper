import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Sprint 11: category budgets. Monthly limits on spending categories; rollover (owner decision 17) carries what
/// was left, or overspent, into the next month, from the month the budget was created.
struct BudgetTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: zone) }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var parts = DateComponents(year: year, month: month, day: day, hour: 12)
        parts.timeZone = zone
        return calendar.calendar.date(from: parts)!
    }

    // MARK: Math

    struct RolloverCase: Sendable, CustomTestStringConvertible {
        let label: String
        let rollsOver: Bool
        /// Spending in July, August, September (minor units).
        let spent: [Int64]
        let expectedCarried: Int64
        let expectedRemaining: Int64
        var testDescription: String { label }
    }

    static let rolloverCases = [
        RolloverCase(
            label: "leftovers carry", rollsOver: true, spent: [20_000, 25_000, 10_000], expectedCarried: 15_000,
            expectedRemaining: 35_000),
        RolloverCase(
            label: "overspend takes from the next month", rollsOver: true, spent: [40_000, 30_000, 5_000],
            expectedCarried: -10_000, expectedRemaining: 15_000),
        RolloverCase(
            label: "off: every month starts at the limit", rollsOver: false, spent: [0, 0, 10_000],
            expectedCarried: 0, expectedRemaining: 20_000),
    ]

    @Test(arguments: rolloverCases)
    func rolloverCarriesBothWaysFromTheStartMonth(_ entry: RolloverCase) throws {
        let dining = UUID()
        let rule = BudgetRule(
            categoryID: dining, limit: cad(30_000), rollsOver: entry.rollsOver,
            startMonth: calendar.startOfMonth(for: date(2026, 7, 1)))
        var lines: [BudgetLine] = []
        for (index, amount) in entry.spent.enumerated() where amount > 0 {
            lines.append(BudgetLine(categoryID: dining, amount: cad(amount), occurredAt: date(2026, 7 + index, 10)))
        }
        // Spending before the budget existed never counts.
        lines.append(BudgetLine(categoryID: dining, amount: cad(99_000), occurredAt: date(2026, 6, 10)))
        let status = try #require(
            try BudgetCalculator().statuses([rule], lines: lines, month: date(2026, 9, 15), calendar: calendar).first)
        #expect(status.carriedIn == cad(entry.expectedCarried))
        #expect(status.available == cad(30_000 + entry.expectedCarried))
        #expect(status.remaining == cad(entry.expectedRemaining))
    }

    @Test func monthBoundariesFollowTheHouseholdCalendar() throws {
        let dining = UUID()
        let rule = BudgetRule(
            categoryID: dining, limit: cad(10_000), rollsOver: false,
            startMonth: calendar.startOfMonth(for: date(2026, 9, 1)))
        let lastMinute = calendar.startOfMonth(for: date(2026, 10, 1)).addingTimeInterval(-60)
        let firstMinute = calendar.startOfMonth(for: date(2026, 10, 1)).addingTimeInterval(60)
        let lines = [
            BudgetLine(categoryID: dining, amount: cad(1_000), occurredAt: lastMinute),
            BudgetLine(categoryID: dining, amount: cad(2_000), occurredAt: firstMinute),
        ]
        let september = try BudgetCalculator().statuses(
            [rule], lines: lines, month: date(2026, 9, 2), calendar: calendar)
        #expect(september.first?.spent == cad(1_000))
    }

    // MARK: Service

    private struct Fixture {
        let container: ModelContainer
        let ledger: TransactionService
        let categories: CategoryService
        let dining: UUID
        let salary: UUID

        func context() -> ModelContext { ModelContext(container) }
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeFixture() async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let ledger = TransactionService.make(container: container)
        let categories = CategoryService.make(container: container)
        try await ledger.ensureSettings(currencyCode: "CAD", now: now)
        try await categories.seedSystemCategoriesIfNeeded(now: now)
        let all = try ModelContext(container).fetch(FetchDescriptor<CategoryRecord>())
        return Fixture(
            container: container, ledger: ledger, categories: categories,
            dining: try #require(all.first { $0.name == "Dining" }).id,
            salary: try #require(all.first { $0.name == "Salary" }).id)
    }

    private func setBudget(_ fixture: Fixture, _ category: UUID, _ limit: Int64, rollsOver: Bool = true) async throws {
        try await fixture.categories.setBudget(
            for: category, limit: cad(limit), rollsOver: rollsOver, currencyCode: "CAD", now: now, calendar: calendar)
    }

    @Test func onlySpendingCategoriesGetAPositiveLimitInTheHouseholdCurrency() async throws {
        let fixture = try await makeFixture()
        let categories = fixture.categories
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await setBudget(fixture, fixture.salary, 1_000)
        }
        await #expect(throws: LedgerError.nonPositiveAmount) { try await setBudget(fixture, fixture.dining, 0) }
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await categories.setBudget(
                for: fixture.dining, limit: Money(minorUnits: 100, currencyCode: "USD"), rollsOver: true,
                currencyCode: "CAD", now: now, calendar: calendar)
        }
        try await setBudget(fixture, fixture.dining, 30_000)
        try await setBudget(fixture, fixture.dining, 40_000, rollsOver: false)
        let budgets = try fixture.context().fetch(FetchDescriptor<CategoryBudget>())
        #expect(budgets.count == 1, "Setting again edits the one budget")
        #expect(budgets.first?.limit == cad(40_000))
        #expect(budgets.first?.rollsOver == false)
        #expect(budgets.first?.startMonth == calendar.startOfMonth(for: now))
    }

    @Test func theReportCountsPostedSpendingOnlyAndFollowsThePendingSwitch() async throws {
        let fixture = try await makeFixture()
        // A category that takes both income and expenses, so a refund can be filed under it.
        let shared = try await fixture.categories.create(
            name: "Household", icon: "house", color: ColorToken(red: 1, green: 2, blue: 3), kind: .both, now: now)
        try await setBudget(fixture, shared, 30_000)
        let ledger = fixture.ledger
        let hourAgo = now.addingTimeInterval(-3_600)
        func expense(_ amount: Int64, _ status: TransactionStatus = .posted) -> TransactionDraft {
            TransactionDraft(
                amount: cad(amount), type: .expense, occurredAt: hourAgo, status: status, categoryID: shared)
        }
        try await ledger.create(expense(4_000), now: now)
        try await ledger.create(expense(1_000, .pending), now: now)
        try await ledger.create(expense(9_999, .cancelled), now: now)
        // A refund filed under the category doesn't reduce spending (Sprint 11 decision 3).
        try await ledger.create(
            TransactionDraft(amount: cad(500), type: .income, occurredAt: hourAgo, categoryID: shared), now: now)
        var report = try await ledger.budgetReport(month: now, calendar: calendar)
        #expect(report.first?.spent == cad(4_000))
        try await ledger.setAnalyticsIncludesPending(true, now: now)
        report = try await ledger.budgetReport(month: now, calendar: calendar)
        #expect(report.first?.spent == cad(5_000))
        #expect(report.first?.remaining == cad(25_000))
    }

    @Test func deletingOrArchivingACategoryTakesItsBudgetAlong() async throws {
        let fixture = try await makeFixture()
        let categories = fixture.categories
        let coffee = try await categories.create(
            name: "Coffee", icon: "cup.and.saucer", color: ColorToken(red: 1, green: 2, blue: 3), kind: .expense,
            now: now)
        try await setBudget(fixture, coffee, 5_000)
        try await setBudget(fixture, fixture.dining, 30_000)
        try await categories.setArchived(true, category: fixture.dining, now: now)
        let report = try await fixture.ledger.budgetReport(month: now, calendar: calendar)
        #expect(report.map(\.categoryID) == [coffee], "An archived category's budget is hidden")
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await categories.update(
                category: coffee, name: "Coffee", icon: "cup.and.saucer", color: ColorToken(red: 1, green: 2, blue: 3),
                kind: .income, now: now)
        }
        try await categories.delete(category: coffee)
        let left = try fixture.context().fetch(FetchDescriptor<CategoryBudget>()).map(\.categoryID)
        #expect(left == [fixture.dining])
    }

    @Test func aBudgetLocksTheCurrency() async throws {
        let fixture = try await makeFixture()
        let before = try await fixture.ledger.isCurrencyLocked()
        #expect(!before)
        try await setBudget(fixture, fixture.dining, 30_000)
        let after = try await fixture.ledger.isCurrencyLocked()
        #expect(after)
    }

    // MARK: Backups

    @Test func budgetsTravelInBackupsAndAreValidated() async throws {
        let fixture = try await makeFixture()
        try await setBudget(fixture, fixture.dining, 30_000, rollsOver: false)
        let service = BackupService.make(container: fixture.container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(backup.budgets?.count == 1)
        try BackupValidator.validate(backup)

        let target = try await makeFixture()
        _ = try await BackupService.make(container: target.container).restore(backup, availableMedia: [], now: now)
        let restored = try target.context().fetch(FetchDescriptor<CategoryBudget>())
        #expect(restored.map(\.limit) == [cad(30_000)])
        #expect(restored.first?.rollsOver == false)

        var onIncome = backup
        onIncome.budgets?[0].categoryID = fixture.salary
        var twice = backup
        if let first = backup.budgets?.first {
            var copy = first
            copy.id = UUID()
            twice.budgets?.append(copy)
        }
        #expect(throws: BackupError.inconsistentLink(entity: "budgets", field: "categoryID")) {
            try BackupValidator.validate(onIncome)
        }
        #expect(throws: BackupError.duplicateID(entity: "budgets.categoryID")) { try BackupValidator.validate(twice) }
    }
}
