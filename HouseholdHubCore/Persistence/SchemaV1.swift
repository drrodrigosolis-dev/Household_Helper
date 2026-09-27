import Foundation
import SwiftData

// FROZEN since the first install on the owner's iPhone (`063a510`, 2026-09-27). Every stored change is a new schema
// version with a migration stage. The names below resolve to the nested SchemaV1 types.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            AppSettings.self, CategoryRecord.self, Merchant.self, SchemaV1.TransactionRecord.self,
            RecurringTransaction.self, WishlistItem.self, BoardColumn.self, TaskItem.self, SubtaskItem.self,
            Account.self, CategoryBudget.self, SavingsGoal.self,
        ]
    }
}

/// Sprint 20: `TransactionRecord` gains `refundOfTransactionID` (an optional field, so a lightweight migration).
/// Unchanged models are the SchemaV1 classes; only `TransactionRecord` has a V2 class.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.AppSettings.self, SchemaV1.CategoryRecord.self, SchemaV1.Merchant.self,
            SchemaV2.TransactionRecord.self, SchemaV1.RecurringTransaction.self, SchemaV1.WishlistItem.self,
            SchemaV1.BoardColumn.self, SchemaV1.TaskItem.self, SchemaV1.SubtaskItem.self, SchemaV1.Account.self,
            SchemaV1.CategoryBudget.self, SchemaV1.SavingsGoal.self,
        ]
    }
}

public typealias CurrentSchema = SchemaV2

public enum HouseholdMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    /// Never destructive: every stage keeps every record (CLAUDE.md §4).
    public static var stages: [MigrationStage] { [v1ToV2] }

    /// Adds `TransactionRecord.refundOfTransactionID`, nil for every existing record.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
}
