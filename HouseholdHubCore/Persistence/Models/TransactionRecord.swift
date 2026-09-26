import Foundation
import SwiftData

extension SchemaV1 {
    /// A financial event (spec §7.2). Named `TransactionRecord` because `Transaction` collides with SwiftUI's type.
    /// The amount is a positive magnitude; `type` gives the sign.
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

        public var amount: Money {
            Money(minorUnits: amountMinorUnits, currencyCode: currencyCode)
        }

        /// Display accessors fall back for unknown stored values; accounting uses the throwing `ledgerLine()`.
        public var type: TransactionType {
            get { TransactionType(rawValue: typeRawValue) ?? .expense }
            set { typeRawValue = newValue.rawValue }
        }

        public var status: TransactionStatus {
            get { TransactionStatus(rawValue: statusRawValue) ?? .pending }
            set { statusRawValue = newValue.rawValue }
        }

        public var source: TransactionSource {
            get { TransactionSource(rawValue: sourceRawValue) ?? .manual }
            set { sourceRawValue = newValue.rawValue }
        }

        /// Value snapshot for accounting. Unlike the display accessors above, it refuses unknown stored values.
        public func ledgerLine() throws -> LedgerLine {
            guard let type = TransactionType(rawValue: typeRawValue) else {
                throw LedgerError.unreadableRecord(field: "type", value: typeRawValue)
            }
            guard let status = TransactionStatus(rawValue: statusRawValue) else {
                throw LedgerError.unreadableRecord(field: "status", value: statusRawValue)
            }
            return LedgerLine(
                amount: amount, type: type, status: status, occurredAt: occurredAt,
                recurringSeriesID: recurringSeriesID, scheduledOccurrence: scheduledOccurrence)
        }
    }
}

public typealias TransactionRecord = SchemaV1.TransactionRecord
