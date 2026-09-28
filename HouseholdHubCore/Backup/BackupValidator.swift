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
        // Refunds arrived in v3 (Sprint 20); an older file claiming one was not written by this app.
        if original.schemaVersion < 3,
            original.transactions.contains(where: {
                $0.type == TransactionType.refund.rawValue || $0.refundOfTransactionID != nil
            })
        {
            let refund = TransactionType.refund.rawValue
            throw BackupError.invalidValue(entity: "transactions", field: "type", value: refund)
        }
        // Recurring kinds arrived in v4 (Sprint 22); an older file naming one was not written by this app.
        if original.schemaVersion < 4, let kind = original.recurringTransactions.compactMap(\.kind).first {
            throw BackupError.invalidValue(entity: "recurringTransactions", field: "kind", value: kind)
        }
        // Split transactions arrived in v5 (Sprint 23); an older file with a split group was not written by this app.
        if original.schemaVersion < 5, let group = original.transactions.compactMap(\.splitGroupID).first {
            throw BackupError.invalidValue(entity: "transactions", field: "splitGroupID", value: group.uuidString)
        }
        // Task due times arrived in v6 (Sprint 26); an older file with one was not written by this app.
        if original.schemaVersion < 6, let minutes = original.taskItems.compactMap(\.dueTimeMinutes).first {
            throw BackupError.invalidValue(entity: "taskItems", field: "dueTimeMinutes", value: "\(minutes)")
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
            // Bounded, so a hand-edited file can't overflow the rollover sums or make them loop over centuries: a
            // limit up to one billion in major units, a start month between 2000 and the backup's own month.
            guard budget.limitMinorUnits <= maxBudgetMinorUnits else {
                throw BackupError.invalidValue(
                    entity: "budgets", field: "limitMinorUnits", value: "\(budget.limitMinorUnits)")
            }
            let exported = Calendar(identifier: .gregorian).dateComponents(
                in: TimeZone(identifier: "UTC")!, from: backup.exportedAt)
            let start = BudgetMonth(year: budget.startYear, month: budget.startMonth)
            // One month of slack: the export instant is read in UTC, the start month in the household's zone.
            let exportMonth = exported.month ?? 1
            let latest = BudgetMonth(
                year: (exported.year ?? 2000) + (exportMonth == 12 ? 1 : 0), month: exportMonth % 12 + 1)
            guard (1...12).contains(budget.startMonth), start >= BudgetMonth(year: 2000, month: 1), start <= latest
            else {
                throw BackupError.invalidValue(entity: "budgets", field: "start", value: "\(start.year)-\(start.month)")
            }
            try sameCurrency(budget.currencyCode, currency, "budgets")
            let category = backup.categories.first { $0.id == budget.categoryID }
            guard category.flatMap({ CategoryKind(rawValue: $0.kind) })?.allows(.expense) == true else {
                throw BackupError.inconsistentLink(entity: "budgets", field: "categoryID")
            }
        }
        // Savings goals (Sprint 12): a name, a bounded positive target in the household currency, an account that
        // holds money, and at most one goal per wishlist item.
        let goalList = backup.goals ?? []
        _ = try ids(goalList.map(\.id), "goals")
        let goalItems = goalList.compactMap(\.wishlistItemID)
        guard Set(goalItems).count == goalItems.count else {
            throw BackupError.duplicateID(entity: "goals.wishlistItemID")
        }
        for goal in goalList {
            guard !goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupError.invalidValue(entity: "goals", field: "name", value: goal.name)
            }
            try positive(goal.targetMinorUnits, "goals", "targetMinorUnits")
            guard goal.targetMinorUnits <= maxBudgetMinorUnits else {
                throw BackupError.invalidValue(
                    entity: "goals", field: "targetMinorUnits", value: "\(goal.targetMinorUnits)")
            }
            try sameCurrency(goal.currencyCode, currency, "goals")
            try required(goal.accountID, in: accounts, "goals", "accountID")
            let account = accountList.first { $0.id == goal.accountID }
            guard account.flatMap({ AccountKind(rawValue: $0.kind) })?.isLiability == false else {
                throw BackupError.inconsistentLink(entity: "goals", field: "accountID")
            }
            try exists(goal.wishlistItemID, in: wishes, "goals", "wishlistItemID")
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
            if let kind = item.kind {
                try readable(RecurringKind.self, kind, "recurringTransactions", "kind")
            }
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
            // A due time (Sprint 26): minutes after midnight, on a task with a due date.
            if let minutes = task.dueTimeMinutes {
                guard TimeOfDay.isValid(minutes) else {
                    throw BackupError.invalidValue(entity: "taskItems", field: "dueTimeMinutes", value: "\(minutes)")
                }
                guard task.dueDate != nil else {
                    throw BackupError.inconsistentLink(entity: "taskItems", field: "dueTimeMinutes")
                }
            }
            // A repeat (Sprint 13): a valid rule in a known zone, on a task with a due date; rule and zone go together.
            switch (task.recurrenceRule, task.recurrenceTimeZoneIdentifier) {
            case (nil, nil):
                break
            case (let rule?, let zone?):
                guard (try? rule.validate()) != nil else {
                    throw BackupError.invalidValue(entity: "taskItems", field: "recurrenceRule", value: "\(rule)")
                }
                guard TimeZone(identifier: zone) != nil else {
                    throw BackupError.invalidValue(
                        entity: "taskItems", field: "recurrenceTimeZoneIdentifier", value: zone)
                }
                guard task.dueDate != nil else {
                    throw BackupError.inconsistentLink(entity: "taskItems", field: "recurrenceRule")
                }
            default:
                throw BackupError.inconsistentLink(entity: "taskItems", field: "recurrenceTimeZoneIdentifier")
            }
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
            try refundShape(record, purchases: transactions)
        }
        try refundTotals(backup.transactions, purchases: transactions)
        try splitGroups(backup.transactions)
        for item in backup.recurringTransactions {
            // Refunds are only ever made from a purchase, never from a series (Sprint 20).
            guard item.type != TransactionType.refund.rawValue else {
                throw BackupError.invalidValue(entity: "recurringTransactions", field: "type", value: item.type)
            }
            try allows(item.categoryID, item.type, "recurringTransactions")
            try transferShape(
                item.type, item.accountID, item.transferAccountID, item.categoryID, "recurringTransactions")
            if item.type == TransactionType.transfer.rawValue, item.merchantID != nil {
                throw BackupError.inconsistentLink(entity: "recurringTransactions", field: "merchantID")
            }
            // A recurring purchase is always an expense (Sprint 22).
            if item.kind == RecurringKind.purchase.rawValue, item.type != TransactionType.expense.rawValue {
                throw BackupError.inconsistentLink(entity: "recurringTransactions", field: "kind")
            }
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

    /// Largest budget limit or goal target a backup may carry; the same bound the services enforce.
    static let maxBudgetMinorUnits = Money.maxPlanMinorUnits

    /// A refund belongs to one expense in the same account, currency, category and merchant, dated no earlier than
    /// the day before it (the file carries no time zone; the service checks the household day), made by hand and
    /// linked to nothing else. Nothing but a refund names a purchase (Sprint 20).
    private static func refundShape(
        _ record: BackupDTO.Transaction, purchases: [UUID: BackupDTO.Transaction]
    ) throws {
        guard record.type == TransactionType.refund.rawValue else {
            guard record.refundOfTransactionID == nil else {
                throw BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID")
            }
            return
        }
        guard let purchaseID = record.refundOfTransactionID, let purchase = purchases[purchaseID],
            purchase.type == TransactionType.expense.rawValue, purchase.currencyCode == record.currencyCode,
            purchase.accountID == record.accountID, purchase.categoryID == record.categoryID,
            purchase.merchantID == record.merchantID,
            record.occurredAt >= purchase.occurredAt.addingTimeInterval(-86_400)
        else { throw BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID") }
        guard record.source == TransactionSource.manual.rawValue, record.recurringSeriesID == nil,
            record.scheduledOccurrence == nil, record.wishlistItemID == nil
        else { throw BackupError.inconsistentLink(entity: "transactions", field: "source") }
    }

    /// A purchase's posted and pending refunds never add up to more than it cost, never outlive its cancellation, and
    /// are posted only once it is.
    private static func refundTotals(
        _ records: [BackupDTO.Transaction], purchases: [UUID: BackupDTO.Transaction]
    ) throws {
        let cancelled = TransactionStatus.cancelled.rawValue
        let live = records.filter { $0.type == TransactionType.refund.rawValue && $0.status != cancelled }
        for (purchaseID, refunds) in Dictionary(grouping: live, by: { $0.refundOfTransactionID }) {
            guard let purchaseID, let purchase = purchases[purchaseID] else { continue }
            guard purchase.status != cancelled,
                !(purchase.status == TransactionStatus.pending.rawValue
                    && refunds.contains { $0.status == TransactionStatus.posted.rawValue })
            else { throw BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID") }
            var total: Int64 = 0
            for refund in refunds {
                let (sum, overflow) = total.addingReportingOverflow(refund.amountMinorUnits)
                guard !overflow, sum <= purchase.amountMinorUnits else {
                    throw BackupError.inconsistentLink(entity: "transactions", field: "refundOfTransactionID")
                }
                total = sum
            }
        }
    }

    /// The parts of a split (Sprint 23) are one expense or income paid once: at least two records sharing their type,
    /// status, date, account(s), merchant and currency, none a recurring occurrence or wishlist purchase. Refunds and
    /// transfers are never split.
    private static func splitGroups(_ records: [BackupDTO.Transaction]) throws {
        let split = records.filter { $0.splitGroupID != nil }
        for parts in Dictionary(grouping: split, by: { $0.splitGroupID }).values {
            guard parts.count >= 2, let first = parts.first else {
                throw BackupError.inconsistentLink(entity: "transactions", field: "splitGroupID")
            }
            for part in parts {
                guard part.type == TransactionType.expense.rawValue || part.type == TransactionType.income.rawValue,
                    part.type == first.type, part.status == first.status, part.occurredAt == first.occurredAt,
                    part.accountID == first.accountID, part.transferAccountID == first.transferAccountID,
                    part.merchantID == first.merchantID, part.currencyCode == first.currencyCode,
                    part.recurringSeriesID == nil, part.scheduledOccurrence == nil, part.wishlistItemID == nil,
                    part.source != TransactionSource.recurring.rawValue,
                    part.source != TransactionSource.wishlistPurchase.rawValue
                else { throw BackupError.inconsistentLink(entity: "transactions", field: "splitGroupID") }
            }
        }
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
        if var list = goals {
            for index in list.indices {
                if let id = list[index].wishlistItemID, !wishIDs.contains(id) {
                    list[index].wishlistItemID = nil
                    dropped += 1
                }
            }
            goals = list
        }
        // A split needs two parts: a lone part (the rest deleted by a path that missed it) is simply not split.
        let partCounts = Dictionary(transactions.compactMap(\.splitGroupID).map { ($0, 1) }, uniquingKeysWith: +)
        for index in transactions.indices {
            if let group = transactions[index].splitGroupID, partCounts[group] == 1 {
                transactions[index].splitGroupID = nil
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
