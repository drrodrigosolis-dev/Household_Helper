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
