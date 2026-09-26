import Foundation
import SwiftData

extension SchemaV1 {
    /// A recurrence series (spec §7.5). Occurrences are computed, never pre-generated; a record is created only when
    /// the user posts one (§9.4).
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

        public var templateAmount: Money {
            Money(minorUnits: templateAmountMinorUnits, currencyCode: currencyCode)
        }

        public var type: TransactionType {
            get { TransactionType(rawValue: typeRawValue) ?? .expense }
            set { typeRawValue = newValue.rawValue }
        }

        public func rule() throws -> RecurrenceRule {
            try RecurrenceRule.decoded(from: ruleData)
        }

        public func setRule(_ rule: RecurrenceRule) throws {
            try rule.validate()
            ruleData = try rule.encoded()
        }

        public var calendar: HouseholdCalendar {
            HouseholdCalendar(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current)
        }

        /// Value snapshot for accounting; refuses unknown stored values instead of guessing.
        public func series() throws -> RecurringSeries {
            let decodedRule = try rule()
            guard let type = TransactionType(rawValue: typeRawValue) else {
                throw LedgerError.unreadableRecord(field: "type", value: typeRawValue)
            }
            guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
                throw LedgerError.unreadableRecord(field: "timeZone", value: timeZoneIdentifier)
            }
            return RecurringSeries(
                id: id, templateAmount: templateAmount, type: type, rule: decodedRule, timeZone: zone,
                startDate: startDate, endDate: endDate, isEnabled: isEnabled, accountID: accountID,
                transferAccountID: transferAccountID)
        }
    }
}

public typealias RecurringTransaction = SchemaV1.RecurringTransaction
