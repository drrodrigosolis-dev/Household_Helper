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

    /// Sprint 20 and 22: SchemaV1 (frozen at the first iPhone install), SchemaV2 (frozen at its install) and SchemaV3,
    /// one lightweight stage between each pair.
    @Test func migrationPlanGoesFromSchemaV1ThroughSchemaV3() {
        let versions = HouseholdMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions == [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0), Schema.Version(3, 0, 0)])
        #expect(HouseholdMigrationPlan.schemas.first == SchemaV1.self)
        #expect(HouseholdMigrationPlan.schemas.last == CurrentSchema.self)
        #expect(HouseholdMigrationPlan.stages.count == 2)
        #expect(CurrentSchema.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(SchemaV1.models.count == SchemaV2.models.count)
        #expect(SchemaV2.models.count == SchemaV3.models.count)
    }

    /// Each version names its own class for the model it changed and the frozen classes for the rest.
    @Test func eachSchemaVersionUsesItsOwnRecurringClass() {
        let names = { (models: [any PersistentModel.Type]) in models.map { String(reflecting: $0) } }
        #expect(names(SchemaV1.models).contains(String(reflecting: SchemaV1.RecurringTransaction.self)))
        #expect(names(SchemaV2.models).contains(String(reflecting: SchemaV1.RecurringTransaction.self)))
        #expect(names(SchemaV3.models).contains(String(reflecting: SchemaV3.RecurringTransaction.self)))
        #expect(!names(SchemaV3.models).contains(String(reflecting: SchemaV1.RecurringTransaction.self)))
        #expect(names(SchemaV3.models).contains(String(reflecting: SchemaV2.TransactionRecord.self)))
    }

    /// Sprint 20, the owner's real data: a store written by SchemaV1 (as installed at `063a510`) opens through the
    /// app's factory and migration plan (now through SchemaV2 to SchemaV3) with every record and field intact, new
    /// refund links empty and every series a bill.
    @Test func aSchemaV1StoreOnDiskMigratesToTheCurrentSchemaWithEveryRecord() throws {
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
        let categoryID = UUID()
        let seriesID = UUID()
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
            let column = SchemaV1.BoardColumn(name: "To Do", sortOrder: 0, isSystem: true, now: now)
            context.insert(column)
            // One row of every other model, so each entity SchemaV2 shares with SchemaV1 is shown to survive.
            context.insert(SchemaV1.AppSettings(currencyCode: "CAD", now: now))
            let category = SchemaV1.CategoryRecord(
                id: categoryID, name: "Shopping", icon: "bag", color: .black, kind: .expense, sortOrder: 0, now: now)
            context.insert(category)
            context.insert(SchemaV1.Merchant(displayName: "Store", now: now))
            let series = try SchemaV1.RecurringTransaction(
                id: seriesID, templateAmount: Money(minorUnits: 120_000, currencyCode: "CAD"), type: .expense,
                rule: .monthlyOnDay(day: 1), timeZone: TimeZone(identifier: "America/Vancouver")!, startDate: now,
                now: now)
            context.insert(series)
            context.insert(
                SchemaV1.Account(
                    id: account, name: "Main", kind: .bank, startingBalance: Money(minorUnits: 0, currencyCode: "CAD"),
                    startingBalanceDate: now, sortOrder: 0, now: now))
            context.insert(
                SchemaV1.CategoryBudget(
                    categoryID: categoryID, limit: Money(minorUnits: 50_000, currencyCode: "CAD"), rollsOver: true,
                    start: BudgetMonth(year: 2026, month: 9), now: now))
            context.insert(
                SchemaV1.SavingsGoal(
                    name: "Trip", target: Money(minorUnits: 300_000, currencyCode: "CAD"), accountID: account,
                    targetDate: nil, wishlistItemID: nil, sortOrder: 0, now: now))
            let task = SchemaV1.TaskItem(title: "Call", columnID: column.id, priority: .medium, sortOrder: 1, now: now)
            context.insert(task)
            context.insert(SchemaV1.SubtaskItem(title: "Find number", taskID: task.id, sortOrder: 1, now: now))
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
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
        #expect(try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.id) == [categoryID])
        #expect(try context.fetchCount(FetchDescriptor<Merchant>()) == 1)
        let series = try #require(try context.fetch(FetchDescriptor<RecurringTransaction>()).first)
        #expect(series.id == seriesID)
        #expect(try series.series().rule == .monthlyOnDay(day: 1))
        #expect(series.kindRawValue == nil)
        #expect(series.kind == .bill)
        #expect(try context.fetch(FetchDescriptor<Account>()).map(\.id) == [account])
        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).first?.rollsOver == true)
        #expect(try context.fetchCount(FetchDescriptor<SavingsGoal>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SubtaskItem>()) == 1)

        // Opening the migrated store again is a no-op.
        let reopened = try HouseholdContainerFactory().makeContainer(configuration: onDisk)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<TransactionRecord>()) == 2)
    }

    /// Sprint 22, the owner's data since `fd7e67e`: a store written by SchemaV2 opens through the app's factory and
    /// migration plan with every record and field intact, and every existing series reads as a bill.
    @Test func aSchemaV2StoreOnDiskMigratesToSchemaV3WithEveryRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "v2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Household.store")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let coffee = UUID()
        let refund = UUID()
        let account = UUID()
        let categoryID = UUID()
        let merchantID = UUID()
        let rentID = UUID()
        let payID = UUID()
        do {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let v2 = try ModelContainer(
                for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(v2)
            let spent = SchemaV2.TransactionRecord(
                id: coffee, amount: Money(minorUnits: 4_750, currencyCode: "CAD"), type: .expense, status: .posted,
                source: .manual, occurredAt: now, now: now)
            spent.accountID = account
            spent.categoryID = categoryID
            spent.merchantID = merchantID
            spent.merchantNameSnapshot = "Store"
            let back = SchemaV2.TransactionRecord(
                id: refund, amount: Money(minorUnits: 1_000, currencyCode: "CAD"), type: .refund, status: .posted,
                source: .manual, occurredAt: now, now: now)
            back.accountID = account
            back.refundOfTransactionID = coffee
            context.insert(spent)
            context.insert(back)
            context.insert(SchemaV1.AppSettings(currencyCode: "CAD", now: now))
            context.insert(
                SchemaV1.CategoryRecord(
                    id: categoryID, name: "Shopping", icon: "bag", color: .black, kind: .expense, sortOrder: 0,
                    now: now))
            context.insert(SchemaV1.Merchant(id: merchantID, displayName: "Store", now: now))
            let rent = try SchemaV1.RecurringTransaction(
                id: rentID, templateAmount: Money(minorUnits: 120_000, currencyCode: "CAD"), type: .expense,
                rule: .monthlyOnDay(day: 1), timeZone: TimeZone(identifier: "America/Vancouver")!, startDate: now,
                now: now)
            rent.merchantID = merchantID
            rent.accountID = account
            context.insert(rent)
            let pay = try SchemaV1.RecurringTransaction(
                id: payID, templateAmount: Money(minorUnits: 300_000, currencyCode: "CAD"), type: .income,
                rule: .monthlyOnDay(day: 15), timeZone: TimeZone(identifier: "America/Vancouver")!, startDate: now,
                now: now)
            pay.isEnabled = false
            context.insert(pay)
            context.insert(
                SchemaV1.WishlistItem(
                    name: "bike", estimatedPrice: Money(minorUnits: 25_000, currencyCode: "CAD"), priority: .medium,
                    now: now))
            let column = SchemaV1.BoardColumn(name: "To Do", sortOrder: 0, isSystem: true, now: now)
            context.insert(column)
            context.insert(
                SchemaV1.Account(
                    id: account, name: "Main", kind: .bank, startingBalance: Money(minorUnits: 0, currencyCode: "CAD"),
                    startingBalanceDate: now, sortOrder: 0, now: now))
            context.insert(
                SchemaV1.CategoryBudget(
                    categoryID: categoryID, limit: Money(minorUnits: 50_000, currencyCode: "CAD"), rollsOver: true,
                    start: BudgetMonth(year: 2026, month: 9), now: now))
            context.insert(
                SchemaV1.SavingsGoal(
                    name: "Trip", target: Money(minorUnits: 300_000, currencyCode: "CAD"), accountID: account,
                    targetDate: nil, wishlistItemID: nil, sortOrder: 0, now: now))
            let task = SchemaV1.TaskItem(title: "Call", columnID: column.id, priority: .medium, sortOrder: 1, now: now)
            context.insert(task)
            context.insert(SchemaV1.SubtaskItem(title: "Find number", taskID: task.id, sortOrder: 1, now: now))
            try context.save()
        }

        let onDisk = PersistenceConfiguration(storeURL: url)
        let migrated = try HouseholdContainerFactory().makeContainer(configuration: onDisk)
        let context = ModelContext(migrated)
        let byAmount = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.amountMinorUnits)])
        let records = try context.fetch(byAmount)
        #expect(records.map(\.id) == [refund, coffee])
        #expect(records.first?.refundOfTransactionID == coffee, "Sprint 20 refund links survive")
        #expect(records.last?.merchantNameSnapshot == "Store")
        #expect(records.last?.categoryID == categoryID)
        let bySeries = FetchDescriptor<RecurringTransaction>(sortBy: [SortDescriptor(\.templateAmountMinorUnits)])
        let series = try context.fetch(bySeries)
        #expect(series.map(\.id) == [rentID, payID])
        #expect(series.allSatisfy { $0.kindRawValue == nil && $0.kind == .bill }, "Every existing series is a bill")
        #expect(series.first?.merchantID == merchantID)
        #expect(series.first?.accountID == account)
        #expect(series.last?.isEnabled == false)
        #expect(try series.first?.series().rule == .monthlyOnDay(day: 1))
        #expect(try series.last?.series().type == .income)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 1)
        #expect(try context.fetch(FetchDescriptor<CategoryRecord>()).map(\.id) == [categoryID])
        #expect(try context.fetch(FetchDescriptor<Merchant>()).map(\.id) == [merchantID])
        #expect(try context.fetchCount(FetchDescriptor<WishlistItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BoardColumn>()) == 1)
        #expect(try context.fetch(FetchDescriptor<Account>()).map(\.id) == [account])
        #expect(try context.fetch(FetchDescriptor<CategoryBudget>()).first?.rollsOver == true)
        #expect(try context.fetchCount(FetchDescriptor<SavingsGoal>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SubtaskItem>()) == 1)

        // A migrated series can become a purchase, and opening the store again is a no-op.
        series.first?.kind = .purchase
        try context.save()
        let reopened = ModelContext(try HouseholdContainerFactory().makeContainer(configuration: onDisk))
        let kinds = try reopened.fetch(bySeries).map(\.kind)
        #expect(kinds == [.purchase, .bill])
        #expect(try reopened.fetchCount(FetchDescriptor<TransactionRecord>()) == 2)
    }

    /// Phase 10 migration check: a store written to disk opens again through the factory and its migration plan
    /// with every record intact. The V1 → V3 and V2 → V3 migrations have their own tests above.
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
