import Foundation
import SwiftData

// FROZEN: SchemaV1 since the first install on the owner's iPhone (`063a510`, 2026-09-27), SchemaV2 since its install
// (`fd7e67e`), SchemaV3 since its (`8a9ec36`, 2026-09-28), and SchemaV4 and SchemaV5 since theirs (both with
// `f183138`, 2026-09-28); `FrozenSchemaTests` pins all five hashes. Every stored
// change is a new schema version with a migration stage; a model a new version changes keeps its old class
// (`Persistence/Models/V1`) for the versions before it. The names below resolve to the nested SchemaV1 types.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            AppSettings.self, CategoryRecord.self, Merchant.self, SchemaV1.TransactionRecord.self,
            SchemaV1.RecurringTransaction.self, WishlistItem.self, BoardColumn.self, SchemaV1.TaskItem.self,
            SubtaskItem.self,
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

/// Sprint 22: `RecurringTransaction` gains `kindRawValue` (an optional field, so a lightweight migration; nil reads as
/// a bill). `TransactionRecord` is the SchemaV2 class; the other models are the SchemaV1 classes.
public enum SchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.AppSettings.self, SchemaV1.CategoryRecord.self, SchemaV1.Merchant.self,
            SchemaV2.TransactionRecord.self, SchemaV3.RecurringTransaction.self, SchemaV1.WishlistItem.self,
            SchemaV1.BoardColumn.self, SchemaV1.TaskItem.self, SchemaV1.SubtaskItem.self, SchemaV1.Account.self,
            SchemaV1.CategoryBudget.self, SchemaV1.SavingsGoal.self,
        ]
    }
}

/// Sprint 23: `TransactionRecord` gains `splitGroupID` (an optional field, so a lightweight migration; nil = not
/// split). `RecurringTransaction` is the SchemaV3 class; the other models are the SchemaV1 classes.
public enum SchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.AppSettings.self, SchemaV1.CategoryRecord.self, SchemaV1.Merchant.self,
            SchemaV4.TransactionRecord.self, SchemaV3.RecurringTransaction.self, SchemaV1.WishlistItem.self,
            SchemaV1.BoardColumn.self, SchemaV1.TaskItem.self, SchemaV1.SubtaskItem.self, SchemaV1.Account.self,
            SchemaV1.CategoryBudget.self, SchemaV1.SavingsGoal.self,
        ]
    }
}

/// Sprint 26: `TaskItem` gains `dueTimeMinutes` (an optional field, so a lightweight migration; nil = no time).
/// SchemaV1 to SchemaV4 keep the frozen `SchemaV1.TaskItem`; the other models are SchemaV4's classes.
public enum SchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            SchemaV1.AppSettings.self, SchemaV1.CategoryRecord.self, SchemaV1.Merchant.self,
            SchemaV4.TransactionRecord.self, SchemaV3.RecurringTransaction.self, SchemaV1.WishlistItem.self,
            SchemaV1.BoardColumn.self, SchemaV5.TaskItem.self, SchemaV1.SubtaskItem.self, SchemaV1.Account.self,
            SchemaV1.CategoryBudget.self, SchemaV1.SavingsGoal.self,
        ]
    }
}

public typealias CurrentSchema = SchemaV5

public enum HouseholdMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    /// Never destructive: every stage keeps every record (CLAUDE.md §4).
    public static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4, v4ToV5] }

    /// Adds `TransactionRecord.refundOfTransactionID`, nil for every existing record.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)

    /// Adds `RecurringTransaction.kindRawValue`, nil (a bill) for every existing series.
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)

    /// Adds `TransactionRecord.splitGroupID`, nil (not split) for every existing record.
    static let v3ToV4 = MigrationStage.lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)

    /// Adds `TaskItem.dueTimeMinutes`, nil (no time: reminds at the default time) for every existing task.
    static let v4ToV5 = MigrationStage.lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self)
}
