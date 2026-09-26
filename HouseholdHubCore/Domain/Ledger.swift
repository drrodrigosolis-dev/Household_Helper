import Foundation

/// Value snapshot of a transaction for pure calculations (balances, analytics) off the persistence layer.
public struct LedgerLine: Hashable, Sendable {
    /// Positive magnitude; `type` gives the sign.
    public var amount: Money
    public var type: TransactionType
    public var status: TransactionStatus
    public var occurredAt: Date
    public var recurringSeriesID: UUID?
    public var scheduledOccurrence: Date?
    /// The account the money is in (or leaves, for a transfer); nil only in single-balance calculations.
    public var accountID: UUID?
    /// A transfer's destination account.
    public var transferAccountID: UUID?

    public init(
        amount: Money, type: TransactionType, status: TransactionStatus, occurredAt: Date,
        recurringSeriesID: UUID? = nil, scheduledOccurrence: Date? = nil, accountID: UUID? = nil,
        transferAccountID: UUID? = nil
    ) {
        self.amount = amount
        self.type = type
        self.status = status
        self.occurredAt = occurredAt
        self.recurringSeriesID = recurringSeriesID
        self.scheduledOccurrence = scheduledOccurrence
        self.accountID = accountID
        self.transferAccountID = transferAccountID
    }

    /// Signed effect on one account: income adds and expense subtracts in its own account; a transfer subtracts
    /// from its source and adds to its destination; anything else leaves the account unchanged.
    public func effect(onAccount id: UUID) throws -> Money {
        try AccountEffect.signed(
            amount: amount, type: type, accountID: accountID, transferAccountID: transferAccountID, on: id)
    }

    /// Signed effect on the single household balance: income adds, expense subtracts, transfer is neutral.
    public func balanceEffect() throws -> Money {
        switch type {
        case .income: return amount
        case .expense: return try amount.negated()
        case .transfer: return .zero(amount.currencyCode)
        }
    }
}

/// Value snapshot of a recurring series for pure calculations.
public struct RecurringSeries: Hashable, Sendable {
    public var id: UUID
    public var templateAmount: Money
    public var type: TransactionType
    public var rule: RecurrenceRule
    public var timeZone: TimeZone
    public var startDate: Date
    public var endDate: Date?
    public var isEnabled: Bool
    public var accountID: UUID?
    public var transferAccountID: UUID?

    public init(
        id: UUID = UUID(), templateAmount: Money, type: TransactionType, rule: RecurrenceRule, timeZone: TimeZone,
        startDate: Date, endDate: Date? = nil, isEnabled: Bool = true, accountID: UUID? = nil,
        transferAccountID: UUID? = nil
    ) {
        self.id = id
        self.templateAmount = templateAmount
        self.type = type
        self.rule = rule
        self.timeZone = timeZone
        self.startDate = startDate
        self.endDate = endDate
        self.isEnabled = isEnabled
        self.accountID = accountID
        self.transferAccountID = transferAccountID
    }

    /// Signed effect of one occurrence on an account (see `LedgerLine.effect(onAccount:)`).
    public func effect(onAccount id: UUID) throws -> Money {
        try AccountEffect.signed(
            amount: templateAmount, type: type, accountID: accountID, transferAccountID: transferAccountID, on: id)
    }
}

/// An account's baseline for balance math (spec §9.1: a baseline, not a transaction).
public struct AccountBaseline: Hashable, Sendable {
    public var id: UUID
    public var kind: AccountKind
    public var startingBalance: Money
    public var startingBalanceDate: Date

    public init(id: UUID, kind: AccountKind, startingBalance: Money, startingBalanceDate: Date) {
        self.id = id
        self.kind = kind
        self.startingBalance = startingBalance
        self.startingBalanceDate = startingBalanceDate
    }
}

enum AccountEffect {
    static func signed(
        amount: Money, type: TransactionType, accountID: UUID?, transferAccountID: UUID?, on id: UUID
    ) throws -> Money {
        switch type {
        case .income: return accountID == id ? amount : .zero(amount.currencyCode)
        case .expense: return accountID == id ? try amount.negated() : .zero(amount.currencyCode)
        case .transfer:
            if accountID == id, transferAccountID != id {
                return try amount.negated()
            }
            if transferAccountID == id, accountID != id {
                return amount
            }
            return .zero(amount.currencyCode)
        }
    }
}
