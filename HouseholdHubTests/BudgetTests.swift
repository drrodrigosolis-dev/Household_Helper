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
            label: "a month with no spending carries the whole limit", rollsOver: true, spent: [0, 30_000, 0],
            expectedCarried: 30_000, expectedRemaining: 60_000),
        RolloverCase(
            label: "off: every month starts at the limit", rollsOver: false, spent: [0, 0, 10_000],
            expectedCarried: 0, expectedRemaining: 20_000),
    ]

    @Test(arguments: rolloverCases)
    func rolloverCarriesBothWaysFromTheStartMonth(_ entry: RolloverCase) throws {
        let dining = UUID()
        let rule = BudgetRule(
            categoryID: dining, limit: cad(30_000), rollsOver: entry.rollsOver,
            start: BudgetMonth(year: 2026, month: 7))
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
            categoryID: dining, limit: cad(10_000), rollsOver: false, start: BudgetMonth(year: 2026, month: 9))
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
            for: category, limit: cad(limit), rollsOver: rollsOver, now: now, calendar: calendar)
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
                for: fixture.dining, limit: Money(minorUnits: 100, currencyCode: "USD"), rollsOver: true, now: now,
                calendar: calendar)
        }
        try await setBudget(fixture, fixture.dining, 30_000)
        try await setBudget(fixture, fixture.dining, 40_000, rollsOver: false)
        let budgets = try fixture.context().fetch(FetchDescriptor<CategoryBudget>())
        #expect(budgets.count == 1, "Setting again edits the one budget")
        #expect(budgets.first?.limit == cad(40_000))
        #expect(budgets.first?.rollsOver == false)
        #expect(budgets.first?.start == BudgetMonth(containing: now, calendar: calendar))
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

    // MARK: Review follow-ups (Sprint 11 data-safety review)

    @Test func monthsAcrossTheDaylightSavingChangeMeetExactly() throws {
        let dining = UUID()
        let rule = BudgetRule(
            categoryID: dining, limit: cad(10_000), rollsOver: true, start: BudgetMonth(year: 2026, month: 10))
        // Vancouver leaves DST on Nov 1; spending right after each month starts lands in that month only.
        let november = calendar.startOfMonth(for: date(2026, 11, 15))
        let lines = [
            BudgetLine(categoryID: dining, amount: cad(4_000), occurredAt: november.addingTimeInterval(-1)),
            BudgetLine(categoryID: dining, amount: cad(1_000), occurredAt: november),
        ]
        let status = try #require(
            try BudgetCalculator().statuses([rule], lines: lines, month: date(2026, 11, 20), calendar: calendar).first)
        #expect(status.carriedIn == cad(6_000))
        #expect(status.spent == cad(1_000))
    }

    @Test func theStartMonthDoesNotMoveWithTheDeviceTimeZone() throws {
        let dining = UUID()
        let rule = BudgetRule(
            categoryID: dining, limit: cad(30_000), rollsOver: true, start: BudgetMonth(year: 2026, month: 3))
        let toronto = HouseholdCalendar(timeZone: TimeZone(identifier: "America/Toronto")!)
        let tokyo = HouseholdCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let inToronto = try BudgetCalculator().statuses([rule], lines: [], month: date(2026, 5, 15), calendar: toronto)
        let inTokyo = try BudgetCalculator().statuses([rule], lines: [], month: date(2026, 5, 15), calendar: tokyo)
        #expect(inToronto.first?.carriedIn == cad(60_000), "March and April carry")
        #expect(inTokyo.first?.carriedIn == inToronto.first?.carriedIn)
    }

    @Test func aFutureDatedExpenseInTheMonthCountsAndFractionsHaveEdges() throws {
        let dining = UUID()
        let rule = BudgetRule(
            categoryID: dining, limit: cad(10_000), rollsOver: false, start: BudgetMonth(year: 2026, month: 9))
        let lines = [BudgetLine(categoryID: dining, amount: cad(2_500), occurredAt: date(2026, 9, 29))]
        let status = try #require(
            try BudgetCalculator().statuses([rule], lines: lines, month: date(2026, 9, 2), calendar: calendar).first)
        #expect(status.spent == cad(2_500))
        #expect(status.usedFraction == 0.25)
        let behind = BudgetStatus(
            categoryID: dining, limit: cad(100), carriedIn: cad(-200), available: cad(-100), spent: cad(0),
            remaining: cad(-100))
        #expect(behind.usedFraction == 1)
        #expect(behind.isOver)
        let untouched = BudgetStatus(
            categoryID: dining, limit: cad(100), carriedIn: cad(-100), available: cad(0), spent: cad(0),
            remaining: cad(0))
        #expect(untouched.usedFraction == 0)
    }

    @Test func editingTheLimitRereadsPastMonthsAndTurningRolloverOnStartsAfresh() async throws {
        let fixture = try await makeFixture()
        try await setBudget(fixture, fixture.dining, 30_000)
        let context = fixture.context()
        let stored = try #require(try context.fetch(FetchDescriptor<CategoryBudget>()).first)
        stored.start = BudgetMonth(year: 2026, month: 7)
        try context.save()
        var report = try await fixture.ledger.budgetReport(month: now, calendar: calendar)
        let startMonth = BudgetMonth(containing: now, calendar: calendar)
        let pastMonths = Int64((startMonth.year - 2026) * 12 + startMonth.month - 7)
        #expect(report.first?.carriedIn == cad(30_000 * pastMonths))
        try await setBudget(fixture, fixture.dining, 40_000)
        report = try await fixture.ledger.budgetReport(month: now, calendar: calendar)
        #expect(report.first?.carriedIn == cad(40_000 * pastMonths), "A new limit applies to past months too")
        try await setBudget(fixture, fixture.dining, 40_000, rollsOver: false)
        try await setBudget(fixture, fixture.dining, 40_000, rollsOver: true)
        let restarted = try #require(try fixture.context().fetch(FetchDescriptor<CategoryBudget>()).first)
        #expect(restarted.start == startMonth, "Turning rollover back on starts counting this month")
        report = try await fixture.ledger.budgetReport(month: now, calendar: calendar)
        #expect(report.first?.carriedIn == cad(0))
    }

    @Test func movingSpendingBetweenCategoriesMovesOrRemovesBudgets() async throws {
        let fixture = try await makeFixture()
        let categories = fixture.categories
        let color = ColorToken(red: 1, green: 2, blue: 3)
        let coffee = try await categories.create(
            name: "Coffee", icon: "cup.and.saucer", color: color, kind: .expense, now: now)
        try await setBudget(fixture, coffee, 5_000)
        try await setBudget(fixture, fixture.dining, 30_000)
        try await fixture.ledger.create(
            TransactionDraft(
                amount: cad(2_000), type: .expense, occurredAt: now.addingTimeInterval(-60), categoryID: coffee),
            now: now)
        try await categories.reassignAndDelete(from: coffee, to: fixture.dining, now: now)
        let left = try fixture.context().fetch(FetchDescriptor<CategoryBudget>()).map(\.categoryID)
        #expect(left == [fixture.dining], "The deleted category's budget goes with it")
        let report = try await fixture.ledger.budgetReport(month: now, calendar: calendar)
        #expect(report.first?.spent == cad(2_000), "Moved spending counts in the new category's budget")
    }

    @Test func restoringOverABudgetWithAnotherIdKeepsTheBackupsBudget() async throws {
        let fixture = try await makeFixture()
        try await setBudget(fixture, fixture.dining, 30_000)
        let service = BackupService.make(container: fixture.container)
        let backup = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        // Removed and added again: same category, a new budget id.
        try await fixture.categories.removeBudget(for: fixture.dining)
        try await setBudget(fixture, fixture.dining, 12_000)
        _ = try await service.restore(backup, availableMedia: [], now: now)
        let restored = try fixture.context().fetch(FetchDescriptor<CategoryBudget>())
        #expect(restored.map(\.id) == backup.budgets?.map(\.id))
        #expect(restored.map(\.limit) == [cad(30_000)])

        var older = backup
        older.budgets = nil
        _ = try await service.restore(older, availableMedia: [], now: now)
        let afterOlder = try fixture.context().fetch(FetchDescriptor<CategoryBudget>())
        #expect(afterOlder.isEmpty, "A file without budgets has none")
    }

    @Test func theValidatorBoundsBudgets() async throws {
        let fixture = try await makeFixture()
        try await setBudget(fixture, fixture.dining, 30_000)
        let service = BackupService.make(container: fixture.container)
        let good = try await service.snapshot(now: now, appVersion: "1") { _ in nil }
        let startMonth = try #require(good.budgets?.first).startMonth
        func variant(_ change: (inout BackupDTO.BudgetDTO) -> Void) -> BackupDTO {
            var copy = good
            if var first = copy.budgets?.first {
                change(&first)
                copy.budgets = [first]
            }
            return copy
        }
        let cases: [(BackupDTO, BackupError)] = [
            (
                variant { $0.limitMinorUnits = 0 },
                .invalidValue(entity: "budgets", field: "limitMinorUnits", value: "0")
            ),
            (variant { $0.currencyCode = "USD" }, .currencyMismatch(entity: "budgets")),
            (variant { $0.categoryID = UUID() }, .missingReference(entity: "budgets", field: "categoryID")),
            (
                variant { $0.limitMinorUnits = BackupValidator.maxBudgetMinorUnits + 1 },
                .invalidValue(
                    entity: "budgets", field: "limitMinorUnits", value: "\(BackupValidator.maxBudgetMinorUnits + 1)")
            ),
            (
                variant { $0.startYear = 1900 },
                .invalidValue(entity: "budgets", field: "start", value: "1900-\(startMonth)")
            ),
        ]
        for (backup, expected) in cases {
            #expect(throws: expected) { try BackupValidator.validate(backup) }
        }
    }
}
