import Foundation
import SwiftData

// SchemaV1 may change freely until the first release; after that, every stored change needs a new VersionedSchema.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            AppSettings.self, CategoryRecord.self, Merchant.self, TransactionRecord.self, RecurringTransaction.self,
            WishlistItem.self, BoardColumn.self, TaskItem.self, SubtaskItem.self, Account.self, CategoryBudget.self,
            SavingsGoal.self,
        ]
    }
}

public typealias CurrentSchema = SchemaV1

public enum HouseholdMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    public static var stages: [MigrationStage] { [] }
}
