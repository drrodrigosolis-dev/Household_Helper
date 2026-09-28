import Foundation
import SwiftData

/// One part of a split payment (Sprint 23): its own amount, category and note. Everything else (type, status, date,
/// account, merchant, source) is the original's, shared by every part.
public struct SplitPart: Equatable, Sendable {
    public var amount: Money
    public var categoryID: UUID?
    /// Nil or blank keeps the original's note.
    public var notes: String?

    public init(amount: Money, categoryID: UUID?, notes: String? = nil) {
        self.amount = amount
        self.categoryID = categoryID
        self.notes = notes
    }

    /// What is left to assign: `total` less every amount, negative when they add up to more. The split editor's
    /// "Left to assign" and the service's check are this one sum.
    public static func remaining(of total: Money, after amounts: [Money]) throws -> Money {
        try total.subtracting(Money.sum(amounts, currencyCode: total.currencyCode))
    }

    /// The amount that makes the parts add up to `total` given the `others` entered (the split editor's first part
    /// until the user types in it); nil when the others already take all of it or more, or the sum can't be computed.
    public static func balancingAmount(of total: Money, after others: [Money]) -> Money? {
        guard let left = try? remaining(of: total, after: others), left.minorUnits > 0 else { return nil }
        return left
    }
}

extension TransactionService {
    /// How many parts a split may have.
    public static let splitPartCount: ClosedRange<Int> = 2...10

    // MARK: Duplicate

    /// Records the same payment again (Sprint 23): a new manual transaction with the original's amount, type,
    /// category, merchant, note and account(s), dated today at the original's time of day (now, if that time is still
    /// to come), posted, or pending when the original is. It is linked to nothing: no series, wishlist item, refund or
    /// split. A refund (made only from its purchase) and a cancelled record are refused. A category archived since is
    /// left off, as a new entry can't use it.
    @discardableResult
    public func duplicateTransaction(_ id: UUID, now: Date, calendar: HouseholdCalendar) throws -> UUID {
        begin()
        let original = try requireTransaction(id)
        let line = try original.ledgerLine()
        guard line.type != .refund, line.status != .cancelled else { throw LedgerError.notDuplicable }
        let timeOfDay = original.occurredAt.timeIntervalSince(calendar.startOfDay(for: original.occurredAt))
        let occurredAt = min(calendar.startOfDay(for: now).addingTimeInterval(timeOfDay), now)
        let categoryID = try activeCategory(original.categoryID, for: line.type)
        let draft = TransactionDraft(
            amount: line.amount, type: line.type, occurredAt: occurredAt,
            status: line.status == .pending ? .pending : .posted, categoryID: categoryID,
            merchantName: line.type == .transfer ? nil : original.merchantNameSnapshot, notes: original.notes,
            source: .manual, accountID: original.accountID, transferAccountID: original.transferAccountID)
        return try create(draft, now: now)
    }

    private func activeCategory(_ id: UUID?, for type: TransactionType) throws -> UUID? {
        guard let id, type != .transfer else { return nil }
        let descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        guard let category = try modelContext.fetch(descriptor).first, !category.isArchived, category.kind.allows(type)
        else { return nil }
        return category.id
    }

    // MARK: Split

    /// Splits one payment into 2 to 10 parts that add up to it exactly (Sprint 23). The original keeps its id and
    /// becomes the first part (its amount, category and note become the first part's); each other part is a new
    /// record with the original's type, status, date, account, merchant and source. Every part carries the same new
    /// `splitGroupID`. The total is unchanged, so every balance is too. Refused for a transfer, refund, cancelled
    /// record, recurring occurrence or wishlist purchase, a purchase with refunds, and a record already split.
    /// Returns every part's id, the original's first.
    @discardableResult
    public func splitTransaction(_ id: UUID, into parts: [SplitPart], now: Date) throws -> [UUID] {
        begin()
        let record = try requireTransaction(id)
        let line = try record.ledgerLine()
        try requireSplittable(record, line: line)
        guard Self.splitPartCount.contains(parts.count), let first = parts.first else {
            throw LedgerError.splitPartCount
        }
        for part in parts {
            guard part.amount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
            guard part.amount.currencyCode == record.currencyCode else {
                throw LedgerError.currencyMismatch(expected: record.currencyCode, actual: part.amount.currencyCode)
            }
            if let categoryID = part.categoryID {
                // The original's own category may stay even if archived since; a newly picked one must be active.
                try requireUsableCategory(categoryID, for: line.type, allowArchived: categoryID == record.categoryID)
            }
        }
        guard try SplitPart.remaining(of: line.amount, after: parts.map(\.amount)).isZero else {
            throw LedgerError.splitDoesNotAddUp
        }
        let group = UUID()
        // At least a millisecond after the original, so the original stays the first part by creation time; a backup
        // keeps dates to the millisecond.
        let stamp = max(now, record.createdAt.addingTimeInterval(0.001))
        var ids = [record.id]
        for part in parts.dropFirst() {
            let copy = TransactionRecord(
                amount: part.amount, type: line.type, status: line.status, source: record.source,
                occurredAt: record.occurredAt, now: stamp)
            copy.accountID = record.accountID
            copy.merchantID = record.merchantID
            copy.merchantNameSnapshot = record.merchantNameSnapshot
            copy.categoryID = part.categoryID
            copy.notes = Self.splitNote(part.notes) ?? record.notes
            copy.splitGroupID = group
            modelContext.insert(copy)
            ids.append(copy.id)
        }
        if first.categoryID != record.categoryID {
            record.isAIClassified = false
        }
        record.amountMinorUnits = first.amount.minorUnits
        record.categoryID = first.categoryID
        record.notes = Self.splitNote(first.notes) ?? record.notes
        record.splitGroupID = group
        record.updatedAt = now
        try commit()
        return ids
    }

    /// Merges a split back into one record (Sprint 23): the first part keeps its id, category and note and takes the
    /// sum of the parts; the other parts are deleted, and a task linked to one of them links the merged record. Refused
    /// while a part has refunds (they belong to that part) or the parts no longer share type, status, date, account
    /// and merchant. Returns the merged record's id.
    @discardableResult
    public func unsplitTransaction(_ id: UUID, now: Date) throws -> UUID {
        begin()
        let parts = try unsplittableParts(of: id)
        guard let first = parts.first else { throw LedgerError.notSplit }
        let total = try Money.sum(parts.map(\.amount), currencyCode: first.currencyCode)
        let others = Array(parts.dropFirst())
        // Fetched before the first edit, so a failed fetch leaves nothing pending.
        var tasks: [TaskItem] = []
        for other in others {
            let target: UUID? = other.id
            tasks += try modelContext.fetch(
                FetchDescriptor<TaskItem>(predicate: #Predicate { $0.linkedTransactionID == target }))
        }
        for task in tasks {
            task.linkedTransactionID = first.id
            task.updatedAt = now
        }
        first.amountMinorUnits = total.minorUnits
        first.splitGroupID = nil
        first.updatedAt = now
        for other in others {
            modelContext.delete(other)
        }
        try commit()
        return first.id
    }

    /// The same checks as `unsplitTransaction`, changing nothing, so the editor can report a refusal before it
    /// closes.
    public func checkUnsplit(_ id: UUID) throws {
        _ = try unsplittableParts(of: id)
    }

    /// Every part of the split `id` belongs to, the first part first; just `id` when it is not split.
    public func splitPartIDs(of id: UUID) throws -> [UUID] {
        try splitParts(of: requireTransaction(id)).map(\.id)
    }

    // MARK: Rules

    private func requireSplittable(_ record: TransactionRecord, line: LedgerLine) throws {
        guard record.splitGroupID == nil else { throw LedgerError.alreadySplit }
        guard line.type == .expense || line.type == .income, line.status == .posted || line.status == .pending,
            record.recurringSeriesID == nil, record.scheduledOccurrence == nil, record.source != .recurring,
            record.source != .wishlistPurchase, record.wishlistItemID == nil
        else { throw LedgerError.notSplittable }
        guard try !hasAnyRefund(record) else { throw LedgerError.purchaseHasRefunds }
    }

    private func unsplittableParts(of id: UUID) throws -> [TransactionRecord] {
        let record = try requireTransaction(id)
        guard record.splitGroupID != nil else { throw LedgerError.notSplit }
        let parts = try splitParts(of: record)
        guard let first = parts.first, parts.allSatisfy({ Self.sharePayment($0, first) }) else {
            throw LedgerError.splitPartsMustAgree
        }
        for part in parts {
            guard try !hasAnyRefund(part) else { throw LedgerError.purchaseHasRefunds }
        }
        return parts
    }

    /// Every part of `record`'s split, ordered by creation then id (so the original comes first); just the record
    /// when it is not split.
    func splitParts(of record: TransactionRecord) throws -> [TransactionRecord] {
        guard let group = record.splitGroupID else { return [record] }
        let target: UUID? = group
        let parts = try modelContext.fetch(
            FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.splitGroupID == target }))
        return parts.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// The other parts of `record`'s split; empty when it is not split.
    func splitSiblings(of record: TransactionRecord) throws -> [TransactionRecord] {
        guard record.splitGroupID != nil else { return [] }
        return try splitParts(of: record).filter { $0.id != record.id }
    }

    /// An edit to one part must keep the parts agreeing: its type can't change (unsplit first), and its new status,
    /// account and date, which every part takes, must still fit each other part's refunds.
    func requireSplitEdit(
        _ record: TransactionRecord, siblings: [TransactionRecord], type: TransactionType,
        status: TransactionStatus, accountID: UUID?, occurredAt: Date
    ) throws {
        guard !siblings.isEmpty else { return }
        guard type == record.type else { throw LedgerError.splitPartsMustAgree }
        for sibling in siblings {
            try requireRefundsStillFit(
                sibling, type: sibling.type, status: status, amount: sibling.amount, accountID: accountID,
                occurredAt: occurredAt)
        }
    }

    /// Gives every other part the edited part's status, date, account and merchant, without saving: the parts of a
    /// split are one payment. The merchant's name as typed goes too, so a renamed store reads the same on every part.
    /// The caller carries the new merchant on to each part's refunds (`carryClassification`).
    func shareSplit(from record: TransactionRecord, to siblings: [TransactionRecord], now: Date) {
        let behind = siblings.filter {
            !Self.sharePayment($0, record) || $0.merchantNameSnapshot != record.merchantNameSnapshot
        }
        for sibling in behind {
            sibling.statusRawValue = record.statusRawValue
            sibling.occurredAt = record.occurredAt
            sibling.accountID = record.accountID
            sibling.transferAccountID = record.transferAccountID
            sibling.merchantID = record.merchantID
            sibling.merchantNameSnapshot = record.merchantNameSnapshot
            sibling.updatedAt = now
        }
    }

    /// A split needs two parts: when a part is deleted and one is left, that one is no longer split. Without saving.
    func leaveSplit(siblings: [TransactionRecord], now: Date) {
        guard siblings.count == 1, let last = siblings.first else { return }
        last.splitGroupID = nil
        last.updatedAt = now
    }

    /// Whether two parts still describe one payment: the same type, status, date, account(s), merchant and currency.
    static func sharePayment(_ lhs: TransactionRecord, _ rhs: TransactionRecord) -> Bool {
        lhs.typeRawValue == rhs.typeRawValue && lhs.statusRawValue == rhs.statusRawValue
            && lhs.occurredAt == rhs.occurredAt && lhs.accountID == rhs.accountID
            && lhs.transferAccountID == rhs.transferAccountID && lhs.merchantID == rhs.merchantID
            && lhs.currencyCode == rhs.currencyCode
    }

    private static func splitNote(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
