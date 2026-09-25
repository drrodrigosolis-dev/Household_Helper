import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

struct LedgerServiceTests {
    private let zone = TimeZone(identifier: "America/Vancouver")!
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Fixture {
        let container: ModelContainer
        let transactions: TransactionService
        let categories: CategoryService

        func context() -> ModelContext { ModelContext(container) }
    }

    private func makeFixture(startingBalance: Int64 = 0, asOf: Date? = nil) async throws -> Fixture {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let fixture = Fixture(
            container: container, transactions: .make(container: container), categories: .make(container: container))
        try await fixture.transactions.ensureSettings(currencyCode: "CAD", now: now)
        let balance = Money(minorUnits: startingBalance, currencyCode: "CAD")
        let balanceDate = asOf ?? now.addingTimeInterval(-86_400)
        try await fixture.transactions.setStartingBalance(balance, asOf: balanceDate, now: now)
        return fixture
    }

    private func cad(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currencyCode: "CAD")
    }

    private func categoryID(named name: String, in fixture: Fixture) throws -> UUID {
        let all = try fixture.context().fetch(FetchDescriptor<CategoryRecord>())
        return try #require(all.first { $0.name == name }).id
    }

    // MARK: Transactions

    @Test func draftsAreValidatedBeforeAnythingIsStored() async throws {
        let fixture = try await makeFixture()
        let service = fixture.transactions
        let zero = TransactionDraft(amount: cad(0), type: .expense, occurredAt: now)
        await #expect(throws: LedgerError.nonPositiveAmount) { try await service.create(zero, now: now) }
        let transfer = TransactionDraft(amount: cad(100), type: .transfer, occurredAt: now)
        await #expect(throws: LedgerError.transfersUnavailable) { try await service.create(transfer, now: now) }
        let usd = TransactionDraft(amount: Money(minorUnits: 100, currencyCode: "USD"), type: .expense, occurredAt: now)
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await service.create(usd, now: now)
        }
        let recurring = TransactionDraft(amount: cad(100), type: .expense, occurredAt: now, source: .recurring)
        await #expect(throws: LedgerError.sourceRequiresDedicatedPath(.recurring)) {
            try await service.create(recurring, now: now)
        }
        #expect(try fixture.context().fetchCount(FetchDescriptor<TransactionRecord>()) == 0)
    }

    @Test func categoryMustExistBeActiveAndMatchType() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.seedSystemCategoriesIfNeeded(now: now)
        let salary = try categoryID(named: "Salary", in: fixture)
        let dining = try categoryID(named: "Dining", in: fixture)
        let service = fixture.transactions

        let wrongKind = TransactionDraft(amount: cad(100), type: .expense, occurredAt: now, categoryID: salary)
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await service.create(wrongKind, now: now)
        }
        let unknown = TransactionDraft(amount: cad(100), type: .expense, occurredAt: now, categoryID: UUID())
        await #expect(throws: LedgerError.unknownCategory) { try await service.create(unknown, now: now) }

        try await fixture.categories.setArchived(true, category: dining, now: now)
        let archived = TransactionDraft(amount: cad(100), type: .expense, occurredAt: now, categoryID: dining)
        await #expect(throws: LedgerError.archivedCategory) { try await service.create(archived, now: now) }
    }

    @Test func merchantsAreReusedByNormalizedName() async throws {
        let fixture = try await makeFixture()
        let first = TransactionDraft(amount: cad(450), type: .expense, occurredAt: now, merchantName: "Café Luna")
        let second = TransactionDraft(amount: cad(500), type: .expense, occurredAt: now, merchantName: "  cafe  LUNA ")
        try await fixture.transactions.create(first, now: now)
        try await fixture.transactions.create(second, now: now)

        let context = fixture.context()
        #expect(try context.fetchCount(FetchDescriptor<Merchant>()) == 1)
        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        #expect(Set(records.compactMap(\.merchantID)).count == 1)
        #expect(Set(records.compactMap(\.merchantNameSnapshot)) == ["Café Luna", "  cafe  LUNA "])
    }

    // MARK: Recurring

    private func insertMonthlyRent(in fixture: Fixture, startingAt start: Date) throws -> UUID {
        let context = fixture.context()
        let series = try RecurringTransaction(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone,
            startDate: start, now: now)
        context.insert(series)
        try context.save()
        return series.id
    }

    @Test func anOccurrenceIsMaterializedExactlyOnce() async throws {
        let fixture = try await makeFixture()
        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00-08:00"))
        let seriesID = try insertMonthlyRent(in: fixture, startingAt: start)
        let february = try #require(ISO8601DateFormatter().date(from: "2026-02-01T09:00:00-08:00"))
        let service = fixture.transactions

        try await service.materialize(seriesID: seriesID, occurrence: february, now: now)
        await #expect(throws: LedgerError.alreadyMaterialized) {
            try await service.materialize(seriesID: seriesID, occurrence: february, now: now)
        }
        let notADueDate = february.addingTimeInterval(3600)
        await #expect(throws: LedgerError.notAnOccurrence) {
            try await service.materialize(seriesID: seriesID, occurrence: notADueDate, now: now)
        }
        await #expect(throws: LedgerError.unknownSeries) {
            try await service.materialize(seriesID: UUID(), occurrence: february, now: now)
        }

        let context = fixture.context()
        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.source == .recurring)
        #expect(records.first?.scheduledOccurrence == february)
        let series = try #require(try context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        let march = try #require(ISO8601DateFormatter().date(from: "2026-03-01T09:00:00-08:00"))
        #expect(series.nextOccurrence == march)
    }

    @Test(arguments: [false, true])
    func deletingAnOccurrenceDisablesTheSeriesOnlyWhenAsked(disable: Bool) async throws {
        let fixture = try await makeFixture()
        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00-08:00"))
        let seriesID = try insertMonthlyRent(in: fixture, startingAt: start)
        let recordID = try await fixture.transactions.materialize(seriesID: seriesID, occurrence: start, now: now)

        try await fixture.transactions.deleteTransaction(recordID, alsoDisableSeries: disable, now: now)

        let context = fixture.context()
        #expect(try context.fetchCount(FetchDescriptor<TransactionRecord>()) == 0)
        let series = try #require(try context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(series.isEnabled == !disable)
    }

    @Test func balanceSnapshotReadsTheStore() async throws {
        let startDate = now.addingTimeInterval(-10 * 86_400)
        let fixture = try await makeFixture(startingBalance: 100_000, asOf: startDate)
        let expense = TransactionDraft(amount: cad(4750), type: .expense, occurredAt: now.addingTimeInterval(-3600))
        let pending = TransactionDraft(
            amount: cad(2000), type: .expense, occurredAt: now.addingTimeInterval(-60), status: .pending)
        try await fixture.transactions.create(expense, now: now)
        try await fixture.transactions.create(pending, now: now)

        let snapshot = try await fixture.transactions.balanceSnapshot(
            now: now, calendar: HouseholdCalendar(timeZone: zone), includePendingInProjection: true)
        #expect(snapshot.current == cad(95_250))
        #expect(snapshot.pendingImpact == cad(-2000))
        #expect(snapshot.projected == cad(93_250))
    }

    // MARK: Categories

    @Test func systemCategoriesSeedOnceAndAreReadable() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.seedSystemCategoriesIfNeeded(now: now)
        try await fixture.categories.seedSystemCategoriesIfNeeded(now: now)
        let count = try fixture.context().fetchCount(FetchDescriptor<CategoryRecord>())
        #expect(count == SystemCategory.defaults.count)
        for seed in SystemCategory.defaults {
            #expect(seed.color.meetsAAContrast(against: .white, largeText: true), "\(seed.name) contrast")
        }
    }

    @Test func referencedCategoriesCannotBeDeletedOnlyArchivedOrReassigned() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.seedSystemCategoriesIfNeeded(now: now)
        let dining = try categoryID(named: "Dining", in: fixture)
        let groceries = try categoryID(named: "Groceries", in: fixture)
        let salary = try categoryID(named: "Salary", in: fixture)
        let categories = fixture.categories

        let custom = CategoryRecord(
            name: "Coffee", icon: "cup.and.saucer", color: .black, kind: .expense, sortOrder: 99, now: now)
        let context = fixture.context()
        context.insert(custom)
        try context.save()
        let coffee = custom.id
        let draft = TransactionDraft(amount: cad(450), type: .expense, occurredAt: now, categoryID: coffee)
        try await fixture.transactions.create(draft, now: now)

        await #expect(throws: LedgerError.systemCategoryIsPermanent) { try await categories.delete(category: dining) }
        await #expect(throws: LedgerError.categoryInUse(transactionCount: 1)) {
            try await categories.delete(category: coffee)
        }
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await categories.reassign(from: coffee, to: salary, now: now)
        }
        #expect(try await categories.reassign(from: coffee, to: groceries, now: now) == 1)
        try await categories.delete(category: coffee)

        let records = try fixture.context().fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.map(\.categoryID) == [groceries])
    }
}
