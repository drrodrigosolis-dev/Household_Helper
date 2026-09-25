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
        #expect(fetched.first?.startingBalanceMinorUnits == 0)
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

    @Test func migrationPlanStartsAtSchemaV1() {
        #expect(HouseholdMigrationPlan.schemas.count == 1)
        #expect(HouseholdMigrationPlan.stages.isEmpty)
        #expect(CurrentSchema.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test func onDiskConfigurationNeverUsesCloudKitOrMemory() {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = HouseholdContainerFactory.modelConfiguration(for: .onDisk, schema: schema)
        #expect(config.isStoredInMemoryOnly == false)
        #expect(config.cloudKitContainerIdentifier == nil)
    }
}
