import Foundation
import SwiftData

/// What has been paid and given back on one expense (Sprint 20).
public struct RefundSummary: Equatable, Sendable {
    public let paid: Money
    /// Posted and pending refunds; cancelled ones don't count.
    public let refunded: Money
    public let remaining: Money

    public var isFullyRefunded: Bool { remaining.minorUnits == 0 }
    public var hasRefunds: Bool { refunded.minorUnits > 0 }
}

public struct RefundResult: Equatable, Sendable {
    public let refundID: UUID
    /// Set when this refund completed the refund of a wishlist purchase: the owner chooses what happens to the item
    /// (`resolveRefundedWishlistItem`).
    public let wishlistItemToResolve: UUID?
}

/// The owner's choice for a wishlist item whose purchase was fully refunded (Sprint 20 decision 8).
public enum RefundedItemChoice: Sendable {
    /// Back to Wanted. The old purchase stays in history, unlinked from the item, so it can be bought again.
    case keepOnWishlist
    /// Archived, keeping its link to the purchase as history.
    case removeFromWishlist
}

extension TransactionService {
    public func refundSummary(for purchaseID: UUID) throws -> RefundSummary {
        let purchase = try requireTransaction(purchaseID)
        return try summary(of: purchase, excluding: nil)
    }

    /// Records money given back for one expense: a `refund` in the purchase's account, currency, category and
    /// merchant, dated when the money comes back (not before the purchase's day), for no more than what is left.
    @discardableResult
    public func refundTransaction(
        _ purchaseID: UUID, amount: Money, occurredAt: Date, status: TransactionStatus = .posted, notes: String?,
        calendar: HouseholdCalendar, now: Date
    ) throws -> RefundResult {
        begin()
        let purchase = try requireTransaction(purchaseID)
        try requireRefundable(purchase)
        try requireRefund(
            amount: amount, occurredAt: occurredAt, status: status, of: purchase, excluding: nil, calendar: calendar)
        // Measured before the insert: whether a fetch sees an unsaved insert is not something to depend on.
        let completesRefund = try summary(of: purchase, excluding: nil).remaining.minorUnits == amount.minorUnits
        let item = try purchase.wishlistItemID.flatMap { try wishlistItem($0) }
        let refund = TransactionRecord(
            amount: amount, type: .refund, status: status, source: .manual, occurredAt: occurredAt, now: now)
        refund.refundOfTransactionID = purchase.id
        refund.accountID = purchase.accountID
        refund.categoryID = purchase.categoryID
        refund.merchantID = purchase.merchantID
        refund.merchantNameSnapshot = purchase.merchantNameSnapshot
        refund.notes = Self.trimmed(notes)
        modelContext.insert(refund)
        try commit()
        let resolve = completesRefund && item?.purchasedTransactionID == purchase.id ? item?.id : nil
        return RefundResult(refundID: refund.id, wishlistItemToResolve: resolve)
    }

    /// Changes a refund's amount (within what is left, not counting itself), date, status or note. Its link,
    /// account and category follow the purchase and don't change.
    public func updateRefund(
        _ refundID: UUID, amount: Money, occurredAt: Date, status: TransactionStatus, notes: String?,
        calendar: HouseholdCalendar, now: Date
    ) throws {
        begin()
        let refund = try requireTransaction(refundID)
        guard refund.type == .refund, let purchaseID = refund.refundOfTransactionID else {
            throw LedgerError.refundNeedsPurchase
        }
        let purchase = try requireTransaction(purchaseID)
        if status != .cancelled {
            try requireRefund(
                amount: amount, occurredAt: occurredAt, status: status, of: purchase, excluding: refundID,
                calendar: calendar)
        } else {
            guard amount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
            try requireCurrency(amount, of: purchase)
        }
        refund.amountMinorUnits = amount.minorUnits
        refund.occurredAt = occurredAt
        refund.status = status
        refund.notes = Self.trimmed(notes)
        refund.updatedAt = now
        try commit()
    }

    /// Carries out the owner's choice for a wishlist item after its purchase was fully refunded.
    public func resolveRefundedWishlistItem(_ itemID: UUID, choice: RefundedItemChoice, now: Date) throws {
        begin()
        guard let item = try wishlistItem(itemID), let purchaseID = item.purchasedTransactionID else {
            throw WishlistError.unknownItem
        }
        let purchase = try requireTransaction(purchaseID)
        let totals = try summary(of: purchase, excluding: nil)
        // Only a fully refunded purchase frees its item; a partial refund leaves it Purchased.
        guard totals.isFullyRefunded else { throw LedgerError.notRefundable }
        switch choice {
        case .keepOnWishlist:
            item.status = .wanted
            item.purchasedTransactionID = nil
            item.actualPriceMinorUnits = nil
            purchase.wishlistItemID = nil
            purchase.updatedAt = now
        case .removeFromWishlist:
            item.status = .archived
        }
        item.updatedAt = now
        try commit()
    }

    // MARK: Rules

    /// Live (posted or pending) refunds of `purchase`, optionally leaving one out (the refund being edited).
    func liveRefunds(of purchase: TransactionRecord, excluding: UUID?) throws -> [TransactionRecord] {
        let target: UUID? = purchase.id
        let refundType = TransactionType.refund.rawValue
        let cancelled = TransactionStatus.cancelled.rawValue
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.refundOfTransactionID == target && $0.typeRawValue == refundType
                    && $0.statusRawValue != cancelled
            })
        return try modelContext.fetch(descriptor).filter { $0.id != excluding }
    }

    /// Whether any refund, live or cancelled, points at `purchase`: its history then protects the purchase.
    func hasAnyRefund(_ purchase: TransactionRecord) throws -> Bool {
        let target: UUID? = purchase.id
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.refundOfTransactionID == target })
        return try modelContext.fetchCount(descriptor) > 0
    }

    func summary(of purchase: TransactionRecord, excluding: UUID?) throws -> RefundSummary {
        let paid = purchase.amount
        let refunds = try liveRefunds(of: purchase, excluding: excluding).map(\.amount)
        let refunded = try Money.sum(refunds, currencyCode: paid.currencyCode)
        return RefundSummary(paid: paid, refunded: refunded, remaining: try paid.subtracting(refunded))
    }

    /// A refund made live again (from cancelled) must still fit in what is left on its purchase.
    func requireRefundFits(_ refund: TransactionRecord) throws {
        guard let purchaseID = refund.refundOfTransactionID else { throw LedgerError.refundNeedsPurchase }
        let purchase = try requireTransaction(purchaseID)
        let remaining = try summary(of: purchase, excluding: refund.id).remaining
        guard refund.amountMinorUnits <= remaining.minorUnits else {
            throw LedgerError.refundExceedsRemaining(remaining: remaining)
        }
    }

    private func requireRefundable(_ purchase: TransactionRecord) throws {
        let line = try purchase.ledgerLine()
        guard line.type == .expense, line.status == .posted || line.status == .pending else {
            throw LedgerError.notRefundable
        }
    }

    private func requireRefund(
        amount: Money, occurredAt: Date, status: TransactionStatus, of purchase: TransactionRecord, excluding: UUID?,
        calendar: HouseholdCalendar
    ) throws {
        guard status == .posted || status == .pending else { throw LedgerError.refundMustBeLive }
        guard amount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        try requireCurrency(amount, of: purchase)
        guard calendar.startOfDay(for: occurredAt) >= calendar.startOfDay(for: purchase.occurredAt) else {
            throw LedgerError.refundBeforePurchase
        }
        let remaining = try summary(of: purchase, excluding: excluding).remaining
        guard amount.minorUnits <= remaining.minorUnits else {
            throw LedgerError.refundExceedsRemaining(remaining: remaining)
        }
    }

    private func requireCurrency(_ amount: Money, of purchase: TransactionRecord) throws {
        guard amount.currencyCode == purchase.currencyCode else {
            throw LedgerError.currencyMismatch(expected: purchase.currencyCode, actual: amount.currencyCode)
        }
    }

    /// A purchase with refunds keeps what they depend on (decision 6).
    func requireRefundsStillFit(
        _ purchase: TransactionRecord, type: TransactionType, status: TransactionStatus, amount: Money,
        accountID: UUID?
    ) throws {
        guard try hasAnyRefund(purchase) else { return }
        let refunded = try summary(of: purchase, excluding: nil).refunded
        guard type == .expense, status != .cancelled, amount.currencyCode == purchase.currencyCode,
            accountID == purchase.accountID, amount.minorUnits >= refunded.minorUnits
        else { throw LedgerError.purchaseHasRefunds }
    }

    private static func trimmed(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
