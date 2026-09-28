import Foundation
import SwiftData

/// Every stored field of one transaction, as it was just before a delete (Sprint 23, F3). A value, so it can wait in
/// memory on the main actor for the few seconds the Undo banner shows; it is never persisted.
public struct TransactionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let amountMinorUnits: Int64
    public let currencyCode: String
    public let typeRawValue: String
    public let statusRawValue: String
    public let sourceRawValue: String
    public let occurredAt: Date
    public let merchantID: UUID?
    public let merchantNameSnapshot: String?
    public let categoryID: UUID?
    public let notes: String?
    public let recurringSeriesID: UUID?
    public let scheduledOccurrence: Date?
    public let wishlistItemID: UUID?
    public let isAIClassified: Bool
    public let accountID: UUID?
    public let transferAccountID: UUID?
    public let refundOfTransactionID: UUID?
    public let createdAt: Date
    public let updatedAt: Date

    init(of record: TransactionRecord) {
        id = record.id
        amountMinorUnits = record.amountMinorUnits
        currencyCode = record.currencyCode
        typeRawValue = record.typeRawValue
        statusRawValue = record.statusRawValue
        sourceRawValue = record.sourceRawValue
        occurredAt = record.occurredAt
        merchantID = record.merchantID
        merchantNameSnapshot = record.merchantNameSnapshot
        categoryID = record.categoryID
        notes = record.notes
        recurringSeriesID = record.recurringSeriesID
        scheduledOccurrence = record.scheduledOccurrence
        wishlistItemID = record.wishlistItemID
        isAIClassified = record.isAIClassified
        accountID = record.accountID
        transferAccountID = record.transferAccountID
        refundOfTransactionID = record.refundOfTransactionID
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    /// A new record with the same id and every field as it was.
    func makeRecord() -> TransactionRecord {
        let amount = Money(minorUnits: amountMinorUnits, currencyCode: currencyCode)
        let record = TransactionRecord(
            id: id, amount: amount, type: .expense, status: .posted, source: .manual, occurredAt: occurredAt,
            now: createdAt)
        // The raw values as stored, even ones this version can't read: undo gives back exactly what was there.
        record.typeRawValue = typeRawValue
        record.statusRawValue = statusRawValue
        record.sourceRawValue = sourceRawValue
        record.merchantID = merchantID
        record.merchantNameSnapshot = merchantNameSnapshot
        record.categoryID = categoryID
        record.notes = notes
        record.recurringSeriesID = recurringSeriesID
        record.scheduledOccurrence = scheduledOccurrence
        record.wishlistItemID = wishlistItemID
        record.isAIClassified = isAIClassified
        record.accountID = accountID
        record.transferAccountID = transferAccountID
        record.refundOfTransactionID = refundOfTransactionID
        record.updatedAt = updatedAt
        return record
    }

    /// Whether the record counts in balances and against its purchase: posted or pending.
    var isLive: Bool {
        statusRawValue == TransactionStatus.posted.rawValue || statusRawValue == TransactionStatus.pending.rawValue
    }
}

/// One transaction a delete removed or marked skipped, and the linked state that delete changed (Sprint 23, F3).
public struct DeletedTransaction: Equatable, Sendable {
    /// What the delete did to the record itself (spec §8.3).
    public enum Effect: Equatable, Sendable {
        /// The record was removed from the store.
        case removed
        /// A recurring occurrence stays as a cancelled record, so it is never posted twice; undo gives it back the
        /// status (and update time) it had.
        case markedSkipped
    }

    /// A series the delete disabled ("Delete this occurrence and disable the series").
    struct SeriesState: Equatable, Sendable {
        let id: UUID
        let wasEnabled: Bool
        let updatedAt: Date
    }

    /// The wishlist item a purchase's delete put back to Wanted (spec §8.1).
    struct PurchasedItemState: Equatable, Sendable {
        let itemID: UUID
        let statusRawValue: String
        let actualPriceMinorUnits: Int64?
        let updatedAt: Date
    }

    /// A task whose link to the transaction the delete cleared.
    struct TaskLinkState: Equatable, Sendable {
        let taskID: UUID
        let updatedAt: Date
    }

    public let record: TransactionSnapshot
    public let effect: Effect
    let series: SeriesState?
    let purchasedItem: PurchasedItemState?
    let linkedTasks: [TaskLinkState]
}

/// A bulk Set category edit to one transaction: the category it had, and the one the edit gave it (Sprint 23, F3).
public struct CategoryChange: Equatable, Sendable {
    public let transactionID: UUID
    public let previousCategoryID: UUID?
    /// Whether the previous category was the on-device model's pick; undo restores it with the category.
    public let previousIsAIClassified: Bool
    public let appliedCategoryID: UUID?
}

/// What the Undo banner can take back (Sprint 23, F3). Kept in memory for a few seconds, never persisted.
public enum TransactionUndo: Equatable, Sendable {
    case deletion([DeletedTransaction])
    case categoryChange([CategoryChange])

    /// How many transactions it covers.
    public var count: Int {
        switch self {
        case .deletion(let entries): entries.count
        case .categoryChange(let changes): changes.count
        }
    }
}

/// Why an undo was refused. Every refusal but `partiallyUndone` happens before anything is changed.
public enum UndoError: Error, Equatable, Sendable {
    /// A record with the same id exists again.
    case recordAlreadyExists
    /// Something the record links to (account, category, merchant, series, wishlist item, purchase) is gone.
    case linkTargetMissing
    /// The data moved on since: the record, its item or its purchase changed in a way undo would overwrite or break.
    case changedSince
    /// Some category edits were taken back and `failed` were not.
    case partiallyUndone(failed: Int)
}

/// Sprint 23 (F3): undo for delete and bulk Set category. The snapshot is captured in the same actor turn as the
/// change, so nothing can slip in between; a delete is restored in one save, all of it or none.
extension TransactionService {
    /// Deletes exactly as `deleteTransaction` does, and returns what undo needs to put it all back.
    @discardableResult
    public func deleteTransactionForUndo(_ id: UUID, alsoDisableSeries: Bool, now: Date) throws -> DeletedTransaction {
        begin()
        let record = try requireTransaction(id)
        let isOccurrence = record.recurringSeriesID != nil && record.scheduledOccurrence != nil
        var seriesState: DeletedTransaction.SeriesState?
        if alsoDisableSeries, let seriesID = record.recurringSeriesID, let series = try undoSeries(seriesID) {
            seriesState = .init(id: series.id, wasEnabled: series.isEnabled, updatedAt: series.updatedAt)
        }
        var itemState: DeletedTransaction.PurchasedItemState?
        var taskStates: [DeletedTransaction.TaskLinkState] = []
        if !isOccurrence {
            if let itemID = record.wishlistItemID, let item = try wishlistItem(itemID),
                item.purchasedTransactionID == id
            {
                itemState = .init(
                    itemID: item.id, statusRawValue: item.statusRawValue,
                    actualPriceMinorUnits: item.actualPriceMinorUnits, updatedAt: item.updatedAt)
            }
            taskStates = try undoTasks(linkedTo: id).map { .init(taskID: $0.id, updatedAt: $0.updatedAt) }
        }
        let snapshot = TransactionSnapshot(of: record)
        try deleteTransaction(id, alsoDisableSeries: alsoDisableSeries, now: now)
        return DeletedTransaction(
            record: snapshot, effect: isOccurrence ? .markedSkipped : .removed, series: seriesState,
            purchasedItem: itemState, linkedTasks: taskStates)
    }

    /// Changes a transaction through `update` (so every rule of an edit applies) and returns its previous category.
    @discardableResult
    public func updateCategoryForUndo(_ id: UUID, with draft: TransactionDraft, now: Date) throws -> CategoryChange {
        begin()
        let record = try requireTransaction(id)
        let change = CategoryChange(
            transactionID: id, previousCategoryID: record.categoryID, previousIsAIClassified: record.isAIClassified,
            appliedCategoryID: draft.categoryID)
        try update(id, with: draft, now: now)
        return change
    }

    /// Takes back a delete or a bulk category edit.
    public func undo(_ undo: TransactionUndo, now: Date) throws {
        switch undo {
        case .deletion(let entries): try restore(entries)
        case .categoryChange(let changes): try revert(changes, now: now)
        }
    }

    /// Puts deleted transactions back with their ids and every field, and the linked state their delete changed, in
    /// one save. Refused, with nothing changed, if an id exists again, a link target is gone, or the data moved on.
    public func restore(_ entries: [DeletedTransaction]) throws {
        begin()
        let settings = try requireSettings()
        let restoring = Set(entries.filter { $0.effect == .removed }.map(\.record.id))
        // Every check and fetch happens before the first edit, so a refusal leaves nothing pending.
        var steps: [RestoreStep] = []
        var refundedAmounts: [UUID: Int64] = [:]
        var postedRefundPurchases: Set<UUID> = []
        for entry in entries {
            let snapshot = entry.record
            var step = RestoreStep(entry: entry)
            switch entry.effect {
            case .removed:
                guard try undoTransaction(snapshot.id) == nil else { throw UndoError.recordAlreadyExists }
                guard snapshot.currencyCode == settings.currencyCode else { throw UndoError.changedSince }
                try requireLinkTargets(of: snapshot, restoring: restoring)
                if let state = entry.purchasedItem {
                    guard let item = try wishlistItem(state.itemID) else { throw UndoError.linkTargetMissing }
                    // Bought again since (or purchased by another record): putting the link back would give the item
                    // two purchases.
                    guard item.purchasedTransactionID == nil, item.status != .purchased else {
                        throw UndoError.changedSince
                    }
                    step.item = item
                }
                for state in entry.linkedTasks {
                    // A task deleted or linked elsewhere since keeps what it has; the transaction comes back anyway.
                    if let task = try undoTask(state.taskID), task.linkedTransactionID == nil {
                        step.tasks.append((task, state.updatedAt))
                    }
                }
                if let purchaseID = snapshot.refundOfTransactionID, !restoring.contains(purchaseID), snapshot.isLive {
                    refundedAmounts[purchaseID, default: 0] += snapshot.amountMinorUnits
                    if snapshot.statusRawValue == TransactionStatus.posted.rawValue {
                        postedRefundPurchases.insert(purchaseID)
                    }
                }
            case .markedSkipped:
                guard let record = try undoTransaction(snapshot.id), record.status == .cancelled else {
                    throw UndoError.changedSince
                }
                step.skipped = record
            }
            if let state = entry.series {
                guard let series = try undoSeries(state.id) else { throw UndoError.linkTargetMissing }
                step.series = series
            }
            steps.append(step)
        }
        // Refunds coming back must still fit their purchase: within what is left, and pending while it is.
        for (purchaseID, amount) in refundedAmounts {
            guard let purchase = try undoTransaction(purchaseID) else { throw UndoError.linkTargetMissing }
            let remaining = try summary(of: purchase, excluding: nil).remaining.minorUnits
            guard purchase.type == .expense, purchase.status == .posted || purchase.status == .pending,
                !(purchase.status == .pending && postedRefundPurchases.contains(purchaseID)), amount <= remaining
            else { throw UndoError.changedSince }
        }
        for step in steps {
            applyRestore(step)
        }
        try commit()
    }

    /// Gives each transaction back its previous category through `update`, the path the bulk edit took. Everything
    /// is checked first; a record changed since, or a previous category now archived or gone, refuses the whole undo.
    func revert(_ changes: [CategoryChange], now: Date) throws {
        begin()
        var drafts: [(UUID, TransactionDraft)] = []
        for change in changes {
            guard let record = try undoTransaction(change.transactionID) else { throw UndoError.linkTargetMissing }
            guard record.categoryID == change.appliedCategoryID else { throw UndoError.changedSince }
            let type = try record.ledgerLine().type
            if let previous = change.previousCategoryID {
                guard let category = try undoCategory(previous) else { throw UndoError.linkTargetMissing }
                guard !category.isArchived, category.kind.allows(type) else { throw UndoError.changedSince }
            }
            let draft = TransactionDraft(
                amount: record.amount, type: type, occurredAt: record.occurredAt, status: record.status,
                categoryID: change.previousCategoryID, merchantName: record.merchantNameSnapshot, notes: record.notes,
                isAIClassified: change.previousCategoryID != nil && change.previousIsAIClassified,
                accountID: record.accountID, transferAccountID: record.transferAccountID)
            drafts.append((record.id, draft))
        }
        var failed = 0
        for (id, draft) in drafts {
            do {
                try update(id, with: draft, now: now)
            } catch {
                failed += 1
            }
        }
        guard failed == 0 else { throw UndoError.partiallyUndone(failed: failed) }
    }

    // MARK: Helpers

    /// The models one restored entry touches, fetched and checked before any edit.
    private struct RestoreStep {
        let entry: DeletedTransaction
        var skipped: TransactionRecord?
        var item: WishlistItem?
        var series: RecurringTransaction?
        var tasks: [(TaskItem, Date)] = []
    }

    private func applyRestore(_ step: RestoreStep) {
        let snapshot = step.entry.record
        switch step.entry.effect {
        case .removed:
            modelContext.insert(snapshot.makeRecord())
        case .markedSkipped:
            step.skipped?.statusRawValue = snapshot.statusRawValue
            step.skipped?.updatedAt = snapshot.updatedAt
        }
        if let item = step.item, let state = step.entry.purchasedItem {
            item.purchasedTransactionID = snapshot.id
            item.actualPriceMinorUnits = state.actualPriceMinorUnits
            item.statusRawValue = state.statusRawValue
            item.updatedAt = state.updatedAt
        }
        for (task, updatedAt) in step.tasks {
            task.linkedTransactionID = snapshot.id
            task.updatedAt = updatedAt
        }
        if let series = step.series, let state = step.entry.series {
            series.isEnabled = state.wasEnabled
            series.updatedAt = state.updatedAt
        }
    }

    /// Every id the record points at must still exist; a refund's purchase may be coming back in the same undo.
    private func requireLinkTargets(of snapshot: TransactionSnapshot, restoring: Set<UUID>) throws {
        for accountID in [snapshot.accountID, snapshot.transferAccountID].compactMap({ $0 }) {
            guard try undoAccountExists(accountID) else { throw UndoError.linkTargetMissing }
        }
        if let categoryID = snapshot.categoryID {
            guard try undoCategory(categoryID) != nil else { throw UndoError.linkTargetMissing }
        }
        if let merchantID = snapshot.merchantID {
            guard try undoMerchantExists(merchantID) else { throw UndoError.linkTargetMissing }
        }
        if let seriesID = snapshot.recurringSeriesID {
            guard try undoSeries(seriesID) != nil else { throw UndoError.linkTargetMissing }
        }
        if let itemID = snapshot.wishlistItemID {
            guard try wishlistItem(itemID) != nil else { throw UndoError.linkTargetMissing }
        }
        if let purchaseID = snapshot.refundOfTransactionID, !restoring.contains(purchaseID) {
            guard try undoTransaction(purchaseID) != nil else { throw UndoError.linkTargetMissing }
        }
    }

    private func undoTransaction(_ id: UUID) throws -> TransactionRecord? {
        try modelContext.fetch(FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func undoSeries(_ id: UUID) throws -> RecurringTransaction? {
        try modelContext.fetch(FetchDescriptor<RecurringTransaction>(predicate: #Predicate { $0.id == id })).first
    }

    private func undoCategory(_ id: UUID) throws -> CategoryRecord? {
        try modelContext.fetch(FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func undoTask(_ id: UUID) throws -> TaskItem? {
        try modelContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func undoTasks(linkedTo id: UUID) throws -> [TaskItem] {
        let target: UUID? = id
        return try modelContext.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.linkedTransactionID == target }))
    }

    private func undoAccountExists(_ id: UUID) throws -> Bool {
        try modelContext.fetchCount(FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })) > 0
    }

    private func undoMerchantExists(_ id: UUID) throws -> Bool {
        try modelContext.fetchCount(FetchDescriptor<Merchant>(predicate: #Predicate { $0.id == id })) > 0
    }
}
