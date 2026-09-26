import Foundation

public enum BackupError: Error, Equatable, Sendable {
    /// A backup written by a newer app version, or not a backup at all.
    case unsupportedSchemaVersion(Int)
    case duplicateID(entity: String)
    case invalidValue(entity: String, field: String, value: String)
    case missingReference(entity: String, field: String)
    case currencyMismatch(entity: String)
    case notABackup
}

/// Checks a whole backup before anything is written (spec §26.1: "validate the entire file … before writing
/// anything"). Every rule the services enforce on the way in is checked here too, so a restored store is one the app
/// could have produced itself.
public enum BackupValidator {
    public static func validate(_ backup: BackupDTO) throws {
        guard backup.schemaVersion == BackupDTO.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(backup.schemaVersion)
        }
        let currency = backup.settings.currencyCode
        guard (try? Currency(code: currency)) != nil else {
            throw BackupError.invalidValue(entity: "settings", field: "currencyCode", value: currency)
        }
        try readable(AnalyticsPeriod.self, backup.settings.defaultAnalyticsPeriod, "settings", "defaultAnalyticsPeriod")

        let categories = try ids(backup.categories.map(\.id), "categories")
        let merchants = try ids(backup.merchants.map(\.id), "merchants")
        let transactions = try ids(backup.transactions.map(\.id), "transactions")
        let series = try ids(backup.recurringTransactions.map(\.id), "recurringTransactions")
        let wishes = try ids(backup.wishlistItems.map(\.id), "wishlistItems")
        let columns = try ids(backup.boardColumns.map(\.id), "boardColumns")
        let tasks = try ids(backup.taskItems.map(\.id), "taskItems")
        _ = try ids(backup.subtaskItems.map(\.id), "subtaskItems")

        for category in backup.categories {
            try readable(CategoryKind.self, category.kind, "categories", "kind")
        }
        for merchant in backup.merchants {
            try exists(merchant.defaultCategoryID, in: categories, "merchants", "defaultCategoryID")
        }
        var occurrences = Set<String>()
        for record in backup.transactions {
            try readable(TransactionType.self, record.type, "transactions", "type")
            try readable(TransactionStatus.self, record.status, "transactions", "status")
            try readable(TransactionSource.self, record.source, "transactions", "source")
            try positive(record.amountMinorUnits, "transactions", "amountMinorUnits")
            try sameCurrency(record.currencyCode, currency, "transactions")
            try exists(record.categoryID, in: categories, "transactions", "categoryID")
            try exists(record.merchantID, in: merchants, "transactions", "merchantID")
            try exists(record.recurringSeriesID, in: series, "transactions", "recurringSeriesID")
            try exists(record.wishlistItemID, in: wishes, "transactions", "wishlistItemID")
            if let seriesID = record.recurringSeriesID, let occurrence = record.scheduledOccurrence {
                // One record per occurrence (spec §9.4): a duplicate would post the same occurrence twice.
                let key = "\(seriesID.uuidString)-\(occurrence.timeIntervalSinceReferenceDate)"
                guard occurrences.insert(key).inserted else { throw BackupError.duplicateID(entity: "occurrence") }
            }
        }
        for item in backup.recurringTransactions {
            try readable(TransactionType.self, item.type, "recurringTransactions", "type")
            try positive(item.templateAmountMinorUnits, "recurringTransactions", "templateAmountMinorUnits")
            try sameCurrency(item.currencyCode, currency, "recurringTransactions")
            try exists(item.categoryID, in: categories, "recurringTransactions", "categoryID")
            try exists(item.merchantID, in: merchants, "recurringTransactions", "merchantID")
            guard TimeZone(identifier: item.timeZoneIdentifier) != nil else {
                throw BackupError.invalidValue(
                    entity: "recurringTransactions", field: "timeZoneIdentifier", value: item.timeZoneIdentifier)
            }
            do {
                try item.rule.validate()
            } catch {
                throw BackupError.invalidValue(entity: "recurringTransactions", field: "rule", value: "\(item.rule)")
            }
        }
        for wish in backup.wishlistItems {
            try readable(Priority.self, wish.priority, "wishlistItems", "priority")
            try readable(WishlistStatus.self, wish.status, "wishlistItems", "status")
            try sameCurrency(wish.currencyCode, currency, "wishlistItems")
            let estimate = wish.estimatedPriceMinorUnits
            guard estimate >= 0 else {
                throw BackupError.invalidValue(entity: "wishlistItems", field: "estimatedPrice", value: "\(estimate)")
            }
            if let actual = wish.actualPriceMinorUnits {
                try positive(actual, "wishlistItems", "actualPriceMinorUnits")
            }
            try exists(wish.categoryID, in: categories, "wishlistItems", "categoryID")
            try exists(wish.purchasedTransactionID, in: transactions, "wishlistItems", "purchasedTransactionID")
            try exists(wish.linkedTaskID, in: tasks, "wishlistItems", "linkedTaskID")
            if let reference = wish.mediaReference, !ImageStore.isValidReference(reference) {
                throw BackupError.invalidValue(entity: "wishlistItems", field: "mediaReference", value: reference)
            }
        }
        for task in backup.taskItems {
            try readable(Priority.self, task.priority, "taskItems", "priority")
            try exists(task.columnID, in: columns, "taskItems", "columnID")
            try exists(task.linkedWishlistItemID, in: wishes, "taskItems", "linkedWishlistItemID")
            try exists(task.linkedTransactionID, in: transactions, "taskItems", "linkedTransactionID")
        }
        for subtask in backup.subtaskItems {
            try exists(subtask.taskID, in: tasks, "subtaskItems", "taskID")
        }
        for entry in backup.mediaManifest where !ImageStore.isValidReference(entry.reference) {
            throw BackupError.invalidValue(entity: "mediaManifest", field: "reference", value: entry.reference)
        }
    }

    // MARK: Rules

    private static func ids(_ values: [UUID], _ entity: String) throws -> Set<UUID> {
        let unique = Set(values)
        guard unique.count == values.count else { throw BackupError.duplicateID(entity: entity) }
        return unique
    }

    private static func exists(_ id: UUID?, in known: Set<UUID>, _ entity: String, _ field: String) throws {
        guard let id else { return }
        guard known.contains(id) else { throw BackupError.missingReference(entity: entity, field: field) }
    }

    private static func readable<T: RawRepresentable>(
        _ type: T.Type, _ value: String, _ entity: String, _ field: String
    ) throws where T.RawValue == String {
        guard T(rawValue: value) != nil else {
            throw BackupError.invalidValue(entity: entity, field: field, value: value)
        }
    }

    private static func positive(_ value: Int64, _ entity: String, _ field: String) throws {
        guard value > 0 else { throw BackupError.invalidValue(entity: entity, field: field, value: "\(value)") }
    }

    private static func sameCurrency(_ code: String, _ expected: String, _ entity: String) throws {
        guard code == expected else { throw BackupError.currencyMismatch(entity: entity) }
    }
}
