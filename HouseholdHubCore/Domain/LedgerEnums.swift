import Foundation

public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case income
    case expense
    /// Reserved for multi-account support; hidden in the v1 UI and neutral to the single household balance.
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
