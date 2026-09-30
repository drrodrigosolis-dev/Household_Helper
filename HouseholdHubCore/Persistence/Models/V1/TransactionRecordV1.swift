import Foundation
import SwiftData

extension SchemaV1 {
    /// FROZEN: `TransactionRecord` as first installed on the owner's iPhone (`063a510`). Kept only so SwiftData can
    /// recognize and migrate a V1 store; never used by the app. Do not edit: the store's version hash depends on it.
    @Model
    public final class TransactionRecord {
        @Attribute(.unique) public var id: UUID
        public var amountMinorUnits: Int64
        public var currencyCode: String
        public var typeRawValue: String
        public var statusRawValue: String
        public var sourceRawValue: String
        public var occurredAt: Date
        public var merchantID: UUID?
        /// The merchant name as entered, kept even if the merchant is later renamed or merged (spec §7.4).
        public var merchantNameSnapshot: String?
        public var categoryID: UUID?
        public var notes: String?
        public var recurringSeriesID: UUID?
        /// The recurring occurrence this record materializes; unique per series so it cannot be posted twice.
        public var scheduledOccurrence: Date?
        public var wishlistItemID: UUID?
        public var isAIClassified: Bool
        /// The account the money is in (a transfer's source); the service always sets it (Sprint 10).
        public var accountID: UUID?
        /// A transfer's destination account; nil for income and expenses.
        public var transferAccountID: UUID?
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), amount: Money, type: TransactionType, status: TransactionStatus,
            source: TransactionSource, occurredAt: Date, now: Date
        ) {
            self.id = id
            self.amountMinorUnits = amount.minorUnits
            self.currencyCode = amount.currencyCode
            self.typeRawValue = type.rawValue
            self.statusRawValue = status.rawValue
            self.sourceRawValue = source.rawValue
            self.occurredAt = occurredAt
            self.isAIClassified = false
            self.createdAt = now
            self.updatedAt = now
        }
    }
}
