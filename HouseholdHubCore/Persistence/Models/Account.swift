import Foundation
import SwiftData

extension SchemaV1 {
    /// One of the household's accounts (owner decision 13, Sprint 10): a bank account, savings, a credit card, or
    /// cash. Its starting balance is a baseline, not a transaction (spec §9.1), and it uses the household currency.
    /// The balance is signed: a credit card normally holds a negative balance, the amount owed. Accounts with history
    /// are archived, never deleted.
    @Model
    public final class Account {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var kindRawValue: String
        public var currencyCode: String
        public var startingBalanceMinorUnits: Int64
        public var startingBalanceDate: Date
        public var sortOrder: Int
        public var isArchived: Bool
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), name: String, kind: AccountKind, startingBalance: Money, startingBalanceDate: Date,
            sortOrder: Int, now: Date
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kind.rawValue
            self.currencyCode = startingBalance.currencyCode
            self.startingBalanceMinorUnits = startingBalance.minorUnits
            self.startingBalanceDate = startingBalanceDate
            self.sortOrder = sortOrder
            self.isArchived = false
            self.createdAt = now
            self.updatedAt = now
        }

        public var kind: AccountKind {
            get { AccountKind(rawValue: kindRawValue) ?? .bank }
            set { kindRawValue = newValue.rawValue }
        }

        public var startingBalance: Money {
            Money(minorUnits: startingBalanceMinorUnits, currencyCode: currencyCode)
        }

        /// Value snapshot for balance math; refuses an unknown stored kind instead of guessing.
        public func baseline() throws -> AccountBaseline {
            guard let kind = AccountKind(rawValue: kindRawValue) else {
                throw LedgerError.unreadableRecord(field: "accountKind", value: kindRawValue)
            }
            return AccountBaseline(
                id: id, kind: kind, startingBalance: startingBalance, startingBalanceDate: startingBalanceDate)
        }
    }
}

public typealias Account = SchemaV1.Account
