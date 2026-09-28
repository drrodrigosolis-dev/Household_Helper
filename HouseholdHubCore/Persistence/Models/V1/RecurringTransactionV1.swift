import Foundation
import SwiftData

extension SchemaV1 {
    /// FROZEN: `RecurringTransaction` as first installed on the owner's iPhone (`063a510`) and shared unchanged by
    /// SchemaV2 (`fd7e67e`). Kept only so SwiftData can recognize and migrate a V1 or V2 store; never used by the app.
    /// Do not edit: the store's version hash depends on it.
    @Model
    public final class RecurringTransaction {
        @Attribute(.unique) public var id: UUID
        public var templateAmountMinorUnits: Int64
        public var currencyCode: String
        public var typeRawValue: String
        public var categoryID: UUID?
        public var merchantID: UUID?
        public var notes: String?
        /// JSON-encoded `RecurrenceRule`; stored as data because enums with associated values are not reliable
        /// SwiftData attributes.
        public var ruleData: Data
        /// Calendar context for the rule (spec §10.2), e.g. "America/Vancouver".
        public var timeZoneIdentifier: String
        public var startDate: Date
        public var endDate: Date?
        public var nextOccurrence: Date?
        public var isEnabled: Bool
        /// The account each occurrence lands in (a transfer's source); set by the service (Sprint 10).
        public var accountID: UUID?
        /// A recurring transfer's destination account.
        public var transferAccountID: UUID?
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), templateAmount: Money, type: TransactionType, rule: RecurrenceRule,
            timeZone: TimeZone, startDate: Date, endDate: Date? = nil, now: Date
        ) throws {
            try rule.validate()
            self.id = id
            self.templateAmountMinorUnits = templateAmount.minorUnits
            self.currencyCode = templateAmount.currencyCode
            self.typeRawValue = type.rawValue
            self.ruleData = try rule.encoded()
            self.timeZoneIdentifier = timeZone.identifier
            self.startDate = startDate
            self.endDate = endDate
            self.isEnabled = true
            self.createdAt = now
            self.updatedAt = now
        }
    }
}
