import Foundation

public enum BackupError: Error, Equatable, Sendable {
    /// A backup written by a newer app version, or not a backup at all.
    case unsupportedSchemaVersion(Int)
    case duplicateID(entity: String)
    case invalidValue(entity: String, field: String, value: String)
    case missingReference(entity: String, field: String)
    case currencyMismatch(entity: String)
    /// Two records that must point at each other don't (e.g. a purchase and its wishlist item, spec §8.1).
    case inconsistentLink(entity: String, field: String)
    case notABackup
    case tooLarge(String)
}

/// Checks a whole backup before anything is written (spec §26.1: "validate the entire file … before writing
/// anything"). References must exist, and the invariants the services keep (purchase links both ways, category kinds,
/// task completion, one file per photo) must hold, so a restored store is one the app could have produced itself.
public enum BackupValidator {
    /// Accepts a v1 file by checking its v2 form (`upgradedToCurrent()`), the form a restore writes.
    public static func validate(_ original: BackupDTO) throws {
        guard BackupDTO.readableSchemaVersions.contains(original.schemaVersion) else {
            throw BackupError.unsupportedSchemaVersion(original.schemaVersion)
        }
        // The v1 format required the household baseline; a file without it is not one this app wrote, and upgrading
        // it would invent a zero balance.
        if original.schemaVersion == 1,
            original.settings.startingBalanceMinorUnits == nil || original.settings.startingBalanceDate == nil
        {
            throw BackupError.missingReference(entity: "settings", field: "startingBalance")
        }
        let backup = original.upgradedToCurrent()
        guard backup.schemaVersion == BackupDTO.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(backup.schemaVersion)
        }
        let currency = backup.settings.currencyCode
        guard (try? Currency(code: currency)) != nil else {
            throw BackupError.invalidValue(entity: "settings", field: "currencyCode", value: currency)
        }
        try readable(AnalyticsPeriod.self, backup.settings.defaultAnalyticsPeriod, "settings", "defaultAnalyticsPeriod")

        let accountList = backup.accounts ?? []
        let accounts = try ids(accountList.map(\.id), "accounts")
        for account in accountList {
            try readable(AccountKind.self, account.kind, "accounts", "kind")
            try sameCurrency(account.currencyCode, currency, "accounts")
            guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidValue(entity: "accounts", field: "name", value: account.name)
            }
        }
        // Every entry needs somewhere to go (Sprint 10): a default account that exists and is active.
        guard let defaultAccount = backup.settings.defaultAccountID,
            let main = accountList.first(where: { $0.id == defaultAccount }), !main.isArchived
        else { throw BackupError.missingReference(entity: "settings", field: "defaultAccountID") }
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
        // Budgets (Sprint 11): one per existing category that allows expenses, a positive limit in the household
        // currency.
        let budgetList = backup.budgets ?? []
        _ = try ids(budgetList.map(\.id), "budgets")
        let budgetedCategories = budgetList.map(\.categoryID)
        guard Set(budgetedCategories).count == budgetedCategories.count else {
            throw BackupError.duplicateID(entity: "budgets.categoryID")
        }
        for budget in budgetList {
            try required(budget.categoryID, in: categories, "budgets", "categoryID")
            try positive(budget.limitMinorUnits, "budgets", "limitMinorUnits")
            try sameCurrency(budget.currencyCode, currency, "budgets")
            let category = backup.categories.first { $0.id == budget.categoryID }
            guard category.flatMap({ CategoryKind(rawValue: $0.kind) })?.allows(.expense) == true else {
                throw BackupError.inconsistentLink(entity: "budgets", field: "categoryID")
            }
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
            try required(record.accountID, in: accounts, "transactions", "accountID")
            try exists(record.transferAccountID, in: accounts, "transactions", "transferAccountID")
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
            try required(item.accountID, in: accounts, "recurringTransactions", "accountID")
            try exists(item.transferAccountID, in: accounts, "recurringTransactions", "transferAccountID")
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
        try validateRules(backup)
    }

    /// The invariants the services keep, beyond "every reference exists".
    private static func validateRules(_ backup: BackupDTO) throws {
        let kinds = Dictionary(backup.categories.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        func allows(_ categoryID: UUID?, _ type: String, _ entity: String) throws {
            guard let categoryID, let kind = kinds[categoryID].flatMap(CategoryKind.init(rawValue:)),
                let transactionType = TransactionType(rawValue: type)
            else { return }
            guard kind.allows(transactionType) else {
                throw BackupError.inconsistentLink(entity: entity, field: "categoryID")
            }
        }
        let transactions = Dictionary(backup.transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wishes = Dictionary(backup.wishlistItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in backup.transactions {
            try allows(record.categoryID, record.type, "transactions")
            try transferShape(
                record.type, record.accountID, record.transferAccountID, record.categoryID, "transactions")
            if record.type == TransactionType.transfer.rawValue, record.merchantID != nil {
                throw BackupError.inconsistentLink(entity: "transactions", field: "merchantID")
            }
            if record.source == TransactionSource.recurring.rawValue {
                guard record.recurringSeriesID != nil, record.scheduledOccurrence != nil else {
                    throw BackupError.inconsistentLink(entity: "transactions", field: "recurringSeriesID")
                }
            }
            // A purchase and its item point at each other (spec §8.1).
            if let wishID = record.wishlistItemID, wishes[wishID]?.purchasedTransactionID != record.id {
                throw BackupError.inconsistentLink(entity: "transactions", field: "wishlistItemID")
            }
        }
        for item in backup.recurringTransactions {
            try allows(item.categoryID, item.type, "recurringTransactions")
            try transferShape(
                item.type, item.accountID, item.transferAccountID, item.categoryID, "recurringTransactions")
        }
        var media = Set<String>()
        for wish in backup.wishlistItems {
            try allows(wish.categoryID, TransactionType.expense.rawValue, "wishlistItems")
            if let transactionID = wish.purchasedTransactionID {
                let purchase = transactions[transactionID]
                guard purchase?.wishlistItemID == wish.id else {
                    throw BackupError.inconsistentLink(entity: "wishlistItems", field: "purchasedTransactionID")
                }
                // A purchase stays one live expense (Sprint 3 defaults 9).
                guard purchase?.type == TransactionType.expense.rawValue,
                    purchase?.status != TransactionStatus.cancelled.rawValue
                else {
                    throw BackupError.inconsistentLink(entity: "wishlistItems", field: "purchasedTransactionID")
                }
            } else if wish.status == WishlistStatus.purchased.rawValue {
                throw BackupError.inconsistentLink(entity: "wishlistItems", field: "status")
            }
            if let reference = wish.mediaReference {
                // Two items sharing a file would lose it when either one is deleted.
                guard media.insert(reference).inserted else { throw BackupError.duplicateID(entity: "mediaReference") }
            }
            if let taskID = wish.linkedTaskID,
                backup.taskItems.first(where: { $0.id == taskID })?.linkedWishlistItemID != wish.id
            {
                throw BackupError.inconsistentLink(entity: "wishlistItems", field: "linkedTaskID")
            }
        }
        let manifest = backup.mediaManifest.map(\.reference)
        guard Set(manifest).count == manifest.count else { throw BackupError.duplicateID(entity: "mediaManifest") }
        guard Set(manifest).isSubset(of: media) else {
            throw BackupError.inconsistentLink(entity: "mediaManifest", field: "reference")
        }
        // Tasks on the board are complete exactly when they are in the last column (Sprint 4 default 2).
        let done = backup.boardColumns.max { $0.sortOrder < $1.sortOrder }?.id
        for task in backup.taskItems where task.archivedAt == nil {
            guard (task.columnID == done) == (task.completedAt != nil) else {
                throw BackupError.inconsistentLink(entity: "taskItems", field: "completedAt")
            }
        }
    }

    // MARK: Rules

    private static func ids(_ values: [UUID], _ entity: String) throws -> Set<UUID> {
        let unique = Set(values)
        guard unique.count == values.count else { throw BackupError.duplicateID(entity: entity) }
        return unique
    }

    /// A transfer names two different accounts and no category; nothing else names a destination (Sprint 10).
    private static func transferShape(
        _ type: String, _ source: UUID?, _ destination: UUID?, _ category: UUID?, _ entity: String
    ) throws {
        if type == TransactionType.transfer.rawValue {
            guard destination != nil, destination != source, category == nil else {
                throw BackupError.inconsistentLink(entity: entity, field: "transferAccountID")
            }
        } else if destination != nil {
            throw BackupError.inconsistentLink(entity: entity, field: "transferAccountID")
        }
    }

    private static func required(_ id: UUID?, in known: Set<UUID>, _ entity: String, _ field: String) throws {
        guard let id, known.contains(id) else { throw BackupError.missingReference(entity: entity, field: field) }
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

extension BackupDTO {
    /// Drops optional links that point at nothing (or, for a wishlist item's task, at a task that doesn't point
    /// back), returning how many were dropped. Export uses this so one stale optional link can't make the whole
    /// backup impossible; required references are never touched, so the validator still catches real damage.
    public mutating func droppingDanglingLinks() -> Int {
        let categoryIDs = Set(categories.map(\.id))
        let transactionIDs = Set(transactions.map(\.id))
        let wishIDs = Set(wishlistItems.map(\.id))
        var dropped = 0
        for index in merchants.indices {
            if let id = merchants[index].defaultCategoryID, !categoryIDs.contains(id) {
                merchants[index].defaultCategoryID = nil
                dropped += 1
            }
        }
        for index in taskItems.indices {
            if let id = taskItems[index].linkedWishlistItemID, !wishIDs.contains(id) {
                taskItems[index].linkedWishlistItemID = nil
                dropped += 1
            }
            if let id = taskItems[index].linkedTransactionID, !transactionIDs.contains(id) {
                taskItems[index].linkedTransactionID = nil
                dropped += 1
            }
        }
        let backLinks = Dictionary(
            taskItems.compactMap { task in task.linkedWishlistItemID.map { (task.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        for index in wishlistItems.indices {
            if let taskID = wishlistItems[index].linkedTaskID, backLinks[taskID] != wishlistItems[index].id {
                wishlistItems[index].linkedTaskID = nil
                dropped += 1
            }
        }
        return dropped
    }
}
