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

    private func insertMonthlyRent(in fixture: Fixture, startingAt start: Date) async throws -> UUID {
        try await fixture.transactions.createSeries(
            templateAmount: cad(120_000), type: .expense, rule: .monthlyOnDay(day: 1), timeZone: zone, startDate: start,
            now: now)
    }

    @Test func anOccurrenceIsMaterializedExactlyOnce() async throws {
        let fixture = try await makeFixture()
        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00-08:00"))
        let seriesID = try await insertMonthlyRent(in: fixture, startingAt: start)
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
    func deletingAnOccurrenceLeavesACancelledMarkerAndDisablesOnlyWhenAsked(disable: Bool) async throws {
        let fixture = try await makeFixture()
        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00-08:00"))
        let seriesID = try await insertMonthlyRent(in: fixture, startingAt: start)
        let service = fixture.transactions
        let recordID = try await service.materialize(seriesID: seriesID, occurrence: start, now: now)

        try await service.deleteTransaction(recordID, alsoDisableSeries: disable, now: now)

        let context = fixture.context()
        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.status == .cancelled)
        let series = try #require(try context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(series.isEnabled == !disable)
        if !disable {
            await #expect(throws: LedgerError.alreadyMaterialized) {
                try await service.materialize(seriesID: seriesID, occurrence: start, now: now)
            }
        }
    }

    @Test func deletingAnOrdinaryTransactionRemovesIt() async throws {
        let fixture = try await makeFixture()
        let draft = TransactionDraft(amount: cad(450), type: .expense, occurredAt: now)
        let id = try await fixture.transactions.create(draft, now: now)
        try await fixture.transactions.deleteTransaction(id, alsoDisableSeries: false, now: now)
        #expect(try fixture.context().fetchCount(FetchDescriptor<TransactionRecord>()) == 0)
    }

    @Test func oneServiceInstancePerContainerSoMaterializeCannotRace() async throws {
        let fixture = try await makeFixture()
        #expect(TransactionService.make(container: fixture.container) === fixture.transactions)
        #expect(CategoryService.make(container: fixture.container) === fixture.categories)

        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00-08:00"))
        let seriesID = try await insertMonthlyRent(in: fixture, startingAt: start)
        let first = TransactionService.make(container: fixture.container)
        let second = TransactionService.make(container: fixture.container)
        async let a = try? first.materialize(seriesID: seriesID, occurrence: start, now: now)
        async let b = try? second.materialize(seriesID: seriesID, occurrence: start, now: now)
        let results = await [a, b]
        #expect(results.compactMap { $0 }.count == 1)
        #expect(try fixture.context().fetchCount(FetchDescriptor<TransactionRecord>()) == 1)
    }

    @Test func seriesInputsAreValidated() async throws {
        let fixture = try await makeFixture()
        try await fixture.categories.seedSystemCategoriesIfNeeded(now: now)
        let salary = try categoryID(named: "Salary", in: fixture)
        let service = fixture.transactions
        let rule = RecurrenceRule.monthlyOnDay(day: 1)
        await #expect(throws: LedgerError.nonPositiveAmount) {
            try await service.createSeries(
                templateAmount: cad(0), type: .expense, rule: rule, timeZone: zone, startDate: now, now: now)
        }
        await #expect(throws: LedgerError.transfersUnavailable) {
            try await service.createSeries(
                templateAmount: cad(100), type: .transfer, rule: rule, timeZone: zone, startDate: now, now: now)
        }
        let usd = Money(minorUnits: 100, currencyCode: "USD")
        await #expect(throws: LedgerError.currencyMismatch(expected: "CAD", actual: "USD")) {
            try await service.createSeries(
                templateAmount: usd, type: .expense, rule: rule, timeZone: zone, startDate: now, now: now)
        }
        await #expect(throws: LedgerError.categoryKindMismatch(.income, .expense)) {
            try await service.createSeries(
                templateAmount: cad(100), type: .expense, rule: rule, timeZone: zone, startDate: now,
                categoryID: salary, now: now)
        }
        await #expect(throws: RecurrenceRuleError.self) {
            try await service.createSeries(
                templateAmount: cad(100), type: .expense, rule: .monthlyOnDay(day: 40), timeZone: zone,
                startDate: now, now: now)
        }
        #expect(try fixture.context().fetchCount(FetchDescriptor<RecurringTransaction>()) == 0)
    }

    @Test func settingsAreCreatedOnceAndStartingBalanceCannotBeInTheFuture() async throws {
        let fixture = try await makeFixture()
        try await fixture.transactions.ensureSettings(currencyCode: "CAD", now: now)
        #expect(try fixture.context().fetchCount(FetchDescriptor<AppSettings>()) == 1)
        let service = fixture.transactions
        await #expect(throws: LedgerError.startingBalanceInFuture) {
            try await service.setStartingBalance(cad(100), asOf: now.addingTimeInterval(60), now: now)
        }
    }

    @Test func statusChangesMoveMoneyBetweenPendingAndCurrent() async throws {
        let fixture = try await makeFixture(startingBalance: 10_000)
        let draft = TransactionDraft(
            amount: cad(2500), type: .expense, occurredAt: now.addingTimeInterval(-60), status: .pending)
        let id = try await fixture.transactions.create(draft, now: now)
        let calendar = HouseholdCalendar(timeZone: zone)
        let before = try await fixture.transactions.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        #expect(before.current == cad(10_000))
        #expect(before.pendingImpact == cad(-2500))

        try await fixture.transactions.setStatus(.posted, forTransaction: id, now: now)
        let after = try await fixture.transactions.balanceSnapshot(
            now: now, calendar: calendar, includePendingInProjection: false)
        #expect(after.current == cad(7500))
        #expect(after.pendingImpact == cad(0))
    }

    @Test func unreadableStoredValuesStopBalanceMathInsteadOfGuessing() async throws {
        let fixture = try await makeFixture()
        let context = fixture.context()
        let record = TransactionRecord(
            amount: cad(100), type: .income, status: .posted, source: .manual, occurredAt: now.addingTimeInterval(-60),
            now: now)
        record.typeRawValue = "refund"
        context.insert(record)
        try context.save()
        let service = fixture.transactions
        let calendar = HouseholdCalendar(timeZone: zone)
        await #expect(throws: LedgerError.unreadableRecord(field: "type", value: "refund")) {
            try await service.balanceSnapshot(now: now, calendar: calendar, includePendingInProjection: false)
        }
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

    // MARK: Onboarding and editing

    @Test func onboardingSetsCurrencyAndBalanceAndLocksCurrencyOnceRecordsExist() async throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let service = TransactionService.make(container: container)
        #expect(try await service.settingsSnapshot() == nil)

        let usd = Money(minorUnits: 125_050, currencyCode: "USD")
        let asOf = now.addingTimeInterval(-3600)
        try await service.completeOnboarding(currencyCode: "usd", startingBalance: usd, asOf: asOf, now: now)
        let settings = try #require(try await service.settingsSnapshot())
        #expect(settings.currencyCode == "USD")
        #expect(settings.onboardingCompleted)
        #expect(settings.startingBalance == usd)
        #expect(settings.startingBalanceDate == asOf)

        let draft = TransactionDraft(amount: usd, type: .expense, occurredAt: now)
        try await service.create(draft, now: now)
        await #expect(throws: LedgerError.currencyLockedByExistingRecords) {
            try await service.completeOnboarding(currencyCode: "CAD", startingBalance: cad(0), asOf: asOf, now: now)
        }
    }

    @Test func updateReplacesEditableFieldsAndKeepsProvenance() async throws {
        let fixture = try await makeFixture()
        let start = try #require(ISO8601DateFormatter().date(from: "2026-01-01T09:00:00-08:00"))
        let seriesID = try await insertMonthlyRent(in: fixture, startingAt: start)
        let id = try await fixture.transactions.materialize(seriesID: seriesID, occurrence: start, now: now)

        let edited = TransactionDraft(
            amount: cad(118_000), type: .expense, occurredAt: start, merchantName: "Landlord", notes: "discounted")
        try await fixture.transactions.update(id, with: edited, now: now)

        let record = try #require(try fixture.context().fetch(FetchDescriptor<TransactionRecord>()).first)
        #expect(record.amount == cad(118_000))
        #expect(record.notes == "discounted")
        #expect(record.merchantNameSnapshot == "Landlord")
        #expect(record.source == .recurring)
        #expect(record.recurringSeriesID == seriesID)

        let invalid = TransactionDraft(amount: cad(0), type: .expense, occurredAt: start)
        let service = fixture.transactions
        await #expect(throws: LedgerError.nonPositiveAmount) { try await service.update(id, with: invalid, now: now) }
    }

    @Test func pendingProjectionPreferenceIsStored() async throws {
        let fixture = try await makeFixture()
        #expect(try await fixture.transactions.settingsSnapshot()?.includePendingInProjection == false)
        try await fixture.transactions.setIncludePendingInProjection(true, now: now)
        #expect(try await fixture.transactions.settingsSnapshot()?.includePendingInProjection == true)
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
        try await fixture.transactions.createSeries(
            templateAmount: cad(300), type: .expense, rule: .monthlyOnDay(day: 5), timeZone: zone, startDate: now,
            categoryID: coffee, now: now)
        #expect(try await categories.reassign(from: coffee, to: groceries, now: now) == 1)
        try await categories.delete(category: coffee)

        let after = fixture.context()
        #expect(try after.fetch(FetchDescriptor<TransactionRecord>()).map(\.categoryID) == [groceries])
        #expect(try after.fetch(FetchDescriptor<RecurringTransaction>()).map(\.categoryID) == [groceries])
    }
}
