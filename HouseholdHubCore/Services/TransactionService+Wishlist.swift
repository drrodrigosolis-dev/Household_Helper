import Foundation
import SwiftData

/// Wishlist writes live on the transaction service because a purchase (spec §8.1) and a deletion (§8.2) touch both a
/// wishlist item and a transaction: one serial context makes each of them a single atomic save with no second writer.
extension TransactionService {
    @discardableResult
    public func createWishlistItem(_ draft: WishlistDraft, now: Date) throws -> UUID {
        begin()
        try draft.validate()
        let settings = try requireSettings()
        try requireCurrency(draft.estimatedPrice, settings)
        if let categoryID = draft.categoryID {
            try requireUsableCategory(categoryID, for: .expense)
        }
        let item = WishlistItem(
            name: draft.trimmedName, estimatedPrice: draft.estimatedPrice, priority: draft.priority, now: now)
        apply(draft, to: item)
        item.status = draft.status
        modelContext.insert(item)
        try commit()
        return item.id
    }

    /// Edits the user-facing fields. A purchased or archived item keeps its status; only its details change.
    public func updateWishlistItem(_ id: UUID, with draft: WishlistDraft, now: Date) throws {
        begin()
        let item = try requireWishlistItem(id)
        var checked = draft
        let keepsStatus = item.status == .purchased || item.status == .archived
        if keepsStatus {
            checked.status = .wanted
        }
        try checked.validate()
        try requireItemCurrency(draft.estimatedPrice, item)
        if let categoryID = draft.categoryID {
            try requireUsableCategory(categoryID, for: .expense, allowArchived: categoryID == item.categoryID)
        }
        item.name = draft.trimmedName
        item.estimatedPriceMinorUnits = draft.estimatedPrice.minorUnits
        item.priority = draft.priority
        apply(draft, to: item)
        if !keepsStatus {
            item.status = draft.status
        }
        item.updatedAt = now
        try commit()
    }

    /// Archiving hides an item without touching any transaction; unarchiving restores `purchased` or `wanted`.
    public func setWishlistItemArchived(_ archived: Bool, item id: UUID, now: Date) throws {
        begin()
        let item = try requireWishlistItem(id)
        if archived {
            item.status = .archived
        } else if item.status == .archived {
            item.status = item.purchasedTransactionID == nil ? .wanted : .purchased
        }
        item.updatedAt = now
        try commit()
    }

    /// Deletes the item only (spec §8.2): a linked purchase stays in the ledger, with its link cleared. Returns the
    /// item's media reference so the caller can remove the image file after the delete is saved. An item a savings
    /// goal uses can't be deleted (Sprint 12 decision 6).
    @discardableResult
    public func deleteWishlistItem(_ id: UUID, now: Date) throws -> String? {
        begin()
        // Every fetch happens before the first edit, so a failed fetch leaves no pending edits behind.
        let item = try requireWishlistItem(id)
        let goals = try goalCount(usingWishlistItem: id)
        guard goals == 0 else { throw GoalError.usedByGoals(count: goals) }
        let media = item.mediaReference
        let record = try item.purchasedTransactionID.flatMap { try transaction($0) }
        let itemID: UUID? = id
        let linked = try modelContext.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.linkedWishlistItemID == itemID }))
        if let record {
            record.wishlistItemID = nil
            record.updatedAt = now
        }
        // Tasks linked to the item keep existing; only the link goes (spec §7.8 links are optional).
        for task in linked {
            task.linkedWishlistItemID = nil
            task.updatedAt = now
        }
        modelContext.delete(item)
        try commit()
        return media
    }

    /// Records the media reference after the image file has been written (spec §5.5). Returns the replaced reference.
    @discardableResult
    public func setWishlistMedia(_ reference: String?, item id: UUID, now: Date) throws -> String? {
        begin()
        if let reference {
            guard ImageStore.isValidReference(reference) else { throw WishlistError.invalidMediaReference }
        }
        let item = try requireWishlistItem(id)
        let previous = item.mediaReference
        item.mediaReference = reference
        item.updatedAt = now
        try commit()
        return previous
    }

    /// The purchase conversion (spec §8.1): one expense with source `wishlistPurchase`, linked both ways, and the item
    /// marked purchased, in one save. Every check runs before anything is inserted, so a refusal leaves no trace.
    @discardableResult
    public func purchaseWishlistItem(
        _ id: UUID, actualPrice: Money, occurredAt: Date, categoryID: UUID?, accountID: UUID? = nil, now: Date
    ) throws -> UUID {
        begin()
        let item = try requireWishlistItem(id)
        guard item.status != .purchased, item.purchasedTransactionID == nil else {
            throw WishlistError.alreadyPurchased
        }
        guard item.status != .archived else { throw WishlistError.archived }
        guard actualPrice.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        try requireItemCurrency(actualPrice, item)
        if let categoryID {
            try requireUsableCategory(categoryID, for: .expense, allowArchived: categoryID == item.categoryID)
        }
        // Paid from the default account unless the purchase sheet picked another (Sprint 10 decision 9).
        let account = try resolveAccount(accountID, settings: try requireSettings(), now: now)
        let record = TransactionRecord(
            amount: actualPrice, type: .expense, status: .posted, source: .wishlistPurchase, occurredAt: occurredAt,
            now: now)
        record.accountID = account
        record.categoryID = categoryID
        record.notes = item.name
        record.wishlistItemID = item.id
        modelContext.insert(record)
        item.actualPriceMinorUnits = actualPrice.minorUnits
        item.purchasedTransactionID = record.id
        item.categoryID = categoryID ?? item.categoryID
        item.status = .purchased
        item.updatedAt = now
        try commit()
        return record.id
    }

    // MARK: Helpers

    func wishlistItem(_ id: UUID) throws -> WishlistItem? {
        let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func requireWishlistItem(_ id: UUID) throws -> WishlistItem {
        guard let item = try wishlistItem(id) else { throw WishlistError.unknownItem }
        return item
    }

    private func transaction(_ id: UUID) throws -> TransactionRecord? {
        let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    /// When a purchase's transaction is deleted, the item goes back to `wanted` so history stays consistent.
    func revertPurchase(linkedTo record: TransactionRecord, now: Date) throws {
        guard let itemID = record.wishlistItemID, let item = try wishlistItem(itemID) else { return }
        guard item.purchasedTransactionID == record.id else { return }
        item.purchasedTransactionID = nil
        item.actualPriceMinorUnits = nil
        if item.status == .purchased {
            item.status = .wanted
        }
        item.updatedAt = now
    }

    /// Item amounts are read back in the item's own currency, which must also still be the household's.
    private func requireItemCurrency(_ money: Money, _ item: WishlistItem) throws {
        try requireCurrency(money, try requireSettings())
        guard money.currencyCode == item.currencyCode else {
            throw LedgerError.currencyMismatch(expected: item.currencyCode, actual: money.currencyCode)
        }
    }

    private func apply(_ draft: WishlistDraft, to item: WishlistItem) {
        let notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.categoryID = draft.categoryID
        item.notes = notes?.isEmpty == false ? notes : nil
        item.targetDate = draft.targetDate
    }
}
