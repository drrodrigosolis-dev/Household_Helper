import Foundation

public enum LedgerError: Error, Equatable, Sendable {
    case settingsMissing
    case startingBalanceInFuture
    /// Currency can change freely only while no financial records exist (spec §6.3).
    case currencyLockedByExistingRecords
    /// A stored value this version cannot interpret (e.g. an unknown enum raw value). Accounting paths refuse to
    /// guess, because a wrong guess can flip the sign of a balance.
    case unreadableRecord(field: String, value: String)
    case nonPositiveAmount
    case transfersUnavailable
    case sourceRequiresDedicatedPath(TransactionSource)
    case currencyMismatch(expected: String, actual: String)
    case unknownCategory
    case archivedCategory
    case categoryKindMismatch(CategoryKind, TransactionType)
    case unknownSeries
    case notAnOccurrence
    case alreadyMaterialized
    case unknownTransaction
    case categoryInUse(transactionCount: Int)
    case systemCategoryIsPermanent
}

/// Read-only view of the settings row for the UI, safe to pass across actors.
public struct SettingsSnapshot: Equatable, Sendable {
    public let currencyCode: String
    public let onboardingCompleted: Bool
    public let startingBalance: Money
    public let startingBalanceDate: Date
    public let includePendingInProjection: Bool

    public init(
        currencyCode: String, onboardingCompleted: Bool, startingBalance: Money, startingBalanceDate: Date,
        includePendingInProjection: Bool
    ) {
        self.currencyCode = currencyCode
        self.onboardingCompleted = onboardingCompleted
        self.startingBalance = startingBalance
        self.startingBalanceDate = startingBalanceDate
        self.includePendingInProjection = includePendingInProjection
    }
}

/// A validated request to record a transaction (spec §12.2): every entry path — manual, Quick Add, AI — produces a
/// draft, and only the transaction service turns a draft into a stored record.
public struct TransactionDraft: Equatable, Sendable {
    /// Positive magnitude; `type` gives the sign.
    public var amount: Money
    public var type: TransactionType
    public var status: TransactionStatus
    public var occurredAt: Date
    public var categoryID: UUID?
    public var merchantName: String?
    public var notes: String?
    public var source: TransactionSource

    public init(
        amount: Money, type: TransactionType, occurredAt: Date, status: TransactionStatus = .posted,
        categoryID: UUID? = nil, merchantName: String? = nil, notes: String? = nil, source: TransactionSource = .manual
    ) {
        self.amount = amount
        self.type = type
        self.status = status
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.merchantName = merchantName
        self.notes = notes
        self.source = source
    }

    /// Checks that need no store access. Store-dependent checks (category, currency) happen in the service.
    public func validate() throws {
        guard amount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        guard type != .transfer else { throw LedgerError.transfersUnavailable }
        guard source != .recurring, source != .wishlistPurchase else {
            throw LedgerError.sourceRequiresDedicatedPath(source)
        }
    }
}
