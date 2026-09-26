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
    /// A budget limit, goal target or imported amount above `Money.maxPlanMinorUnits`.
    case amountTooLarge
    /// A transfer needs a destination account other than its source, and only a transfer has one (Sprint 10). A
    /// transfer also carries no category or merchant: it is neither income nor spending.
    case transferNeedsTwoAccounts
    case transferHasNoCategory
    case unknownAccount
    case archivedAccount
    case emptyAccountName
    /// Transactions or recurring items still reference the account; archive it instead (Sprint 10 decision 4).
    case accountInUse(referenceCount: Int)
    /// The default account can't be archived or deleted until another account is the default.
    case defaultAccountRequired
    case sourceRequiresDedicatedPath(TransactionSource)
    case currencyMismatch(expected: String, actual: String)
    case unknownCategory
    case archivedCategory
    case categoryKindMismatch(CategoryKind, TransactionType)
    case unknownSeries
    case notAnOccurrence
    case alreadyMaterialized
    /// Transactions posted from the series still reference it; disable it instead (never delete history silently).
    case seriesHasHistory(postedCount: Int)
    case unknownTransaction
    /// Transactions, series, and wishlist items that still reference the category.
    case categoryInUse(referenceCount: Int)
    /// A wishlist purchase stays one expense (spec §8.1): its type cannot change.
    case purchaseMustStayExpense
    /// Cancelling would leave the item "purchased" with nothing spent; deleting the transaction reverts the item.
    case purchaseCannotBeCancelled
    case systemCategoryIsPermanent
    case emptyCategoryName
}

/// Read-only view of the settings row for the UI, safe to pass across actors.
public struct SettingsSnapshot: Equatable, Sendable {
    public let currencyCode: String
    public let onboardingCompleted: Bool
    /// The default account's baseline (Sprint 10: each account has its own).
    public let startingBalance: Money
    public let startingBalanceDate: Date
    public let includePendingInProjection: Bool
    /// Where new entries go unless another account is picked.
    public let defaultAccountID: UUID?

    public init(
        currencyCode: String, onboardingCompleted: Bool, startingBalance: Money, startingBalanceDate: Date,
        includePendingInProjection: Bool, defaultAccountID: UUID? = nil
    ) {
        self.currencyCode = currencyCode
        self.onboardingCompleted = onboardingCompleted
        self.startingBalance = startingBalance
        self.startingBalanceDate = startingBalanceDate
        self.includePendingInProjection = includePendingInProjection
        self.defaultAccountID = defaultAccountID
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
    /// The category was picked by the on-device model and accepted by the user (spec §12.3). Only meaningful with a
    /// category; an edit that changes the category takes this value, an edit that keeps it keeps the stored one.
    public var isAIClassified: Bool
    /// The account the money is in, or leaves for a transfer; nil means the default account (Sprint 10 decision 8).
    public var accountID: UUID?
    /// A transfer's destination; required for a transfer and absent otherwise.
    public var transferAccountID: UUID?

    public init(
        amount: Money, type: TransactionType, occurredAt: Date, status: TransactionStatus = .posted,
        categoryID: UUID? = nil, merchantName: String? = nil, notes: String? = nil, source: TransactionSource = .manual,
        isAIClassified: Bool = false, accountID: UUID? = nil, transferAccountID: UUID? = nil
    ) {
        self.amount = amount
        self.type = type
        self.status = status
        self.occurredAt = occurredAt
        self.categoryID = categoryID
        self.merchantName = merchantName
        self.notes = notes
        self.source = source
        self.isAIClassified = isAIClassified
        self.accountID = accountID
        self.transferAccountID = transferAccountID
    }

    /// Checks that need no store access. Store-dependent checks (category, currency) happen in the service.
    public func validate() throws {
        guard amount.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        if type == .transfer {
            guard let transferAccountID, transferAccountID != accountID else {
                throw LedgerError.transferNeedsTwoAccounts
            }
            guard categoryID == nil, merchantName == nil else { throw LedgerError.transferHasNoCategory }
        } else {
            guard transferAccountID == nil else { throw LedgerError.transferNeedsTwoAccounts }
        }
        guard source != .recurring, source != .wishlistPurchase else {
            throw LedgerError.sourceRequiresDedicatedPath(source)
        }
    }
}
