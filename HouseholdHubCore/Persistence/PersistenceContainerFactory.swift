import Foundation
import SwiftData

public struct PersistenceConfiguration: Sendable, Equatable {
    public var useInMemoryStore: Bool
    public var appGroupIdentifier: String?

    public init(useInMemoryStore: Bool = false, appGroupIdentifier: String? = nil) {
        self.useInMemoryStore = useInMemoryStore
        self.appGroupIdentifier = appGroupIdentifier
    }

    public static let onDisk = PersistenceConfiguration()
    public static let inMemory = PersistenceConfiguration(useInMemoryStore: true)
}

public protocol PersistenceContainerFactory: Sendable {
    func makeContainer(configuration: PersistenceConfiguration) throws -> ModelContainer
}

/// The single place a Household Hub store is constructed, so the app and widget cannot drift (spec §5.2).
public struct HouseholdContainerFactory: PersistenceContainerFactory {
    public init() {}

    public func makeContainer(configuration: PersistenceConfiguration) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = Self.modelConfiguration(for: configuration, schema: schema)
        return try ModelContainer(for: schema, migrationPlan: HouseholdMigrationPlan.self, configurations: config)
    }

    static func modelConfiguration(for configuration: PersistenceConfiguration, schema: Schema) -> ModelConfiguration {
        if configuration.useInMemoryStore {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        if let identifier = configuration.appGroupIdentifier {
            return ModelConfiguration(schema: schema, groupContainer: .identifier(identifier), cloudKitDatabase: .none)
        }
        return ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .none)
    }
}
