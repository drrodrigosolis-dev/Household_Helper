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

    public init(
        amount: Money, type: TransactionType, status: TransactionStatus, occurredAt: Date,
        recurringSeriesID: UUID? = nil, scheduledOccurrence: Date? = nil
    ) {
        self.amount = amount
        self.type = type
        self.status = status
        self.occurredAt = occurredAt
        self.recurringSeriesID = recurringSeriesID
        self.scheduledOccurrence = scheduledOccurrence
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

    public init(
        id: UUID = UUID(), templateAmount: Money, type: TransactionType, rule: RecurrenceRule, timeZone: TimeZone,
        startDate: Date, endDate: Date? = nil, isEnabled: Bool = true
    ) {
        self.id = id
        self.templateAmount = templateAmount
        self.type = type
        self.rule = rule
        self.timeZone = timeZone
        self.startDate = startDate
        self.endDate = endDate
        self.isEnabled = isEnabled
    }
}
