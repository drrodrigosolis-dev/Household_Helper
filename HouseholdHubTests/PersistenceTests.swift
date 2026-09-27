import Foundation
import SwiftData
import Testing

@testable import HouseholdHubCore

struct PersistenceTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    @Test func inMemoryContainerRoundTripsSettings() throws {
        let container = try HouseholdContainerFactory().makeContainer(configuration: .inMemory)
        let context = ModelContext(container)
        context.insert(AppSettings(currencyCode: "CAD", now: epoch))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.currencyCode == "CAD")
        #expect(fetched.first?.onboardingCompleted == false)
    }

    @Test func inMemoryContainersAreIsolated() throws {
        let factory = HouseholdContainerFactory()
        let first = ModelContext(try factory.makeContainer(configuration: .inMemory))
        let second = ModelContext(try factory.makeContainer(configuration: .inMemory))
        first.insert(AppSettings(currencyCode: "CAD", now: epoch))
        try first.save()

        #expect(try second.fetchCount(FetchDescriptor<AppSettings>()) == 0)
    }

    @Test func ledgerModelsRoundTripWithTypedAccessors() throws {
        let context = ModelContext(try HouseholdContainerFactory().makeContainer(configuration: .inMemory))
        let category = CategoryRecord(
            name: "Groceries", icon: "cart", color: ColorToken(red: 30, green: 136, blue: 229), kind: .expense,
            sortOrder: 0, now: epoch)
        let amount = Money(minorUnits: 3210, currencyCode: "CAD")
        let transaction = TransactionRecord(
            amount: amount, type: .expense, status: .pending, source: .manual, occurredAt: epoch, now: epoch)
        transaction.categoryID = category.id
        let series = try RecurringTransaction(
            templateAmount: amount, type: .expense, rule: .monthlyOnDay(day: 31),
            timeZone: TimeZone(identifier: "America/Vancouver")!, startDate: epoch, now: epoch)
        context.insert(category)
        context.insert(transaction)
        context.insert(series)
        context.insert(Merchant(displayName: "  Café Luna", now: epoch))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<TransactionRecord>()).first)
        #expect(fetched.amount == amount)
        #expect(fetched.type == .expense)
        #expect(fetched.status == .pending)
        #expect(fetched.categoryID == category.id)
        let fetchedCategory = try #require(try context.fetch(FetchDescriptor<CategoryRecord>()).first)
        #expect(fetchedCategory.kind == .expense)
        #expect(fetchedCategory.color == ColorToken(red: 30, green: 136, blue: 229))
        let fetchedSeries = try #require(try context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(try fetchedSeries.rule() == .monthlyOnDay(day: 31))
        #expect(fetchedSeries.timeZoneIdentifier == "America/Vancouver")
        let merchant = try #require(try context.fetch(FetchDescriptor<Merchant>()).first)
        #expect(merchant.normalizedName == "cafe luna")
    }

    @Test func pendingStatusIsFilterableInPredicates() throws {
        let context = ModelContext(try HouseholdContainerFactory().makeContainer(configuration: .inMemory))
        let amount = Money(minorUnits: 100, currencyCode: "CAD")
        for status in [TransactionStatus.posted, .pending, .pending, .cancelled] {
            let record = TransactionRecord(
                amount: amount, type: .expense, status: status, source: .manual, occurredAt: epoch, now: epoch)
            context.insert(record)
        }
        try context.save()
        let pending = TransactionStatus.pending.rawValue
        let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.statusRawValue == pending })
        #expect(try context.fetchCount(descriptor) == 2)
    }

    /// Sprint 20: SchemaV1 (frozen at the first iPhone install) then SchemaV2, one lightweight stage between them.
    @Test func migrationPlanGoesFromSchemaV1ToSchemaV2() {
        #expect(HouseholdMigrationPlan.schemas.count == 2)
        #expect(HouseholdMigrationPlan.schemas.first == SchemaV1.self)
        #expect(HouseholdMigrationPlan.stages.count == 1)
        #expect(CurrentSchema.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(SchemaV1.models.count == SchemaV2.models.count)
    }

    /// Sprint 20, the owner's real data: a store written by SchemaV1 (as installed at `063a510`) opens through the
    /// app's factory and migration plan with every record and field intact, and new refund links empty.
    @Test func aSchemaV1StoreOnDiskMigratesToSchemaV2WithEveryRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "v1-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Household.store")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let coffee = UUID()
        let rent = UUID()
        let bike = UUID()
        let account = UUID()
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let v1 = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(v1)
            let spent = SchemaV1.TransactionRecord(
                id: coffee, amount: Money(minorUnits: 4_750, currencyCode: "CAD"), type: .expense, status: .posted,
                source: .manual, occurredAt: now, now: now)
            spent.notes = "coffee"
            spent.accountID = account
            let paid = SchemaV1.TransactionRecord(
                id: rent, amount: Money(minorUnits: 120_000, currencyCode: "CAD"), type: .expense, status: .pending,
                source: .recurring, occurredAt: now, now: now)
            paid.scheduledOccurrence = now
            context.insert(spent)
            context.insert(paid)
            context.insert(
                SchemaV1.WishlistItem(
                    id: bike, name: "bike", estimatedPrice: Money(minorUnits: 25_000, currencyCode: "CAD"),
                    priority: .medium, now: now))
            context.insert(SchemaV1.BoardColumn(name: "To Do", sortOrder: 0, isSystem: true, now: now))
            try context.save()
        }

        let onDisk = PersistenceConfiguration(storeURL: url)
        let migrated = try HouseholdContainerFactory().makeContainer(configuration: onDisk)
        let context = ModelContext(migrated)
        let byAmount = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.amountMinorUnits)])
        let records = try context.fetch(byAmount)
        #expect(records.map(\.id) == [coffee, rent])
        #expect(records.map(\.amountMinorUnits) == [4_750, 120_000])
        #expect(records.map(\.status) == [.posted, .pending])
        #expect(records.first?.notes == "coffee")
        #expect(records.first?.accountID == account)
        #expect(records.last?.scheduledOccurrence == now)
        #expect(records.allSatisfy { $0.refundOfTransactionID == nil })
        #expect(try context.fetch(FetchDescriptor<WishlistItem>()).map(\.id) == [bike])
        #expect(try context.fetchCount(FetchDescriptor<BoardColumn>()) == 1)

        // Opening the migrated store again is a no-op.
        let reopened = try HouseholdContainerFactory().makeContainer(configuration: onDisk)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<TransactionRecord>()) == 2)
    }

    /// Phase 10 migration check: a store written to disk opens again through the factory and its migration plan
    /// with every record intact. The V1 → V2 migration has its own test above.
    @Test func onDiskStoreReopensThroughTheMigrationPlan() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = PersistenceConfiguration(storeURL: directory.appending(path: "Household.store"))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let backup: BackupDTO
        do {
            let container = try HouseholdContainerFactory().makeContainer(configuration: configuration)
            let ledger = TransactionService.make(container: container)
            try await ledger.completeOnboarding(
                currencyCode: "CAD", startingBalance: Money(minorUnits: 10_000, currencyCode: "CAD"), asOf: now,
                now: now)
            try await CategoryService.make(container: container).seedSystemCategoriesIfNeeded(now: now)
            try await TaskBoardService.make(container: container).seedDefaultColumnsIfNeeded(now: now)
            try await ledger.create(
                TransactionDraft(
                    amount: Money(minorUnits: 4_750, currencyCode: "CAD"), type: .expense, occurredAt: now,
                    notes: "coffee"),
                now: now)
            backup = try await BackupService.make(container: container).snapshot(now: now, appVersion: "1") { _ in nil }
        }
        let reopened = try HouseholdContainerFactory().makeContainer(configuration: configuration)
        let again = try await BackupService.make(container: reopened).snapshot(now: now, appVersion: "1") { _ in nil }
        #expect(again == backup)
        #expect(again.transactions.count == 1)
    }

    @Test func onDiskConfigurationNeverUsesCloudKitOrMemory() {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = HouseholdContainerFactory.modelConfiguration(for: .onDisk, schema: schema)
        #expect(config.isStoredInMemoryOnly == false)
        #expect(config.cloudKitContainerIdentifier == nil)
    }
}
