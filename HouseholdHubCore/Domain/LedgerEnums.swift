import Foundation

public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case income
    case expense
    /// Money moved between two of the household's accounts (Sprint 10): out of one, into the other. Never income or
    /// spending, and neutral to the household total.
    case transfer
}

/// Explicit accounting state (spec §7.2); never a set of booleans.
public enum TransactionStatus: String, Codable, Sendable, CaseIterable {
    case posted
    case pending
    case cancelled
}

/// Provenance only; it never changes accounting meaning.
public enum TransactionSource: String, Codable, Sendable, CaseIterable {
    case manual
    case wishlistPurchase
    case recurring
    case imported
    case widget
    case naturalLanguage
    /// Recorded through the Log Transaction shortcut or Siri (owner decision 2026-09-26).
    case shortcut
}

public enum CategoryKind: String, Codable, Sendable, CaseIterable {
    case income
    case expense
    case both

    /// Whether a category of this kind may classify a transaction of `type` (spec §7.3).
    public func allows(_ type: TransactionType) -> Bool {
        guard type != .transfer else { return false }
        return self == .both || rawValue == type.rawValue
    }
}

/// What an account is (Sprint 10 decision 1). A credit card's balance is normally negative: the amount owed.
public enum AccountKind: String, Codable, Sendable, CaseIterable {
    case bank
    case savings
    case creditCard
    case cash

    /// Whether the account's balance is read as a debt (shown as "owed" when negative).
    public var isLiability: Bool { self == .creditCard }

    /// What a person enters or reads for a stored, signed balance: a card's debt as a positive amount owed.
    public func entered(fromStored stored: Money) throws -> Money {
        isLiability ? try stored.negated() : stored
    }

    /// The signed balance to store for what a person entered: a card's "owed" becomes a negative balance.
    public func stored(fromEntered entered: Money) throws -> Money {
        isLiability ? try entered.negated() : entered
    }
}
