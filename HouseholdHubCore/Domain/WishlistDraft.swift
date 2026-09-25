import Foundation

/// Shared by wishlist items and (Phase 5) tasks; the spec names the type without values (§7.7, §7.8).
public enum Priority: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Lifecycle of a wishlist item (spec §7.7). `purchased` is reachable only through the purchase conversion (§8.1).
public enum WishlistStatus: String, Codable, Sendable, CaseIterable {
    case wanted
    case pending
    case purchased
    case archived
}

public enum WishlistError: Error, Equatable, Sendable {
    case unknownItem
    case emptyName
    case negativeEstimate
    /// Only `wanted` and `pending` may be set directly; `purchased` and `archived` have dedicated operations.
    case statusRequiresDedicatedPath(WishlistStatus)
    case alreadyPurchased
    case archived
    case invalidMediaReference
}

/// The user-editable fields of a wishlist item. Status is limited to `wanted` / `pending` here.
public struct WishlistDraft: Equatable, Sendable {
    public var name: String
    /// Zero means "price unknown"; never negative.
    public var estimatedPrice: Money
    public var priority: Priority
    public var status: WishlistStatus
    public var categoryID: UUID?
    public var notes: String?
    public var targetDate: Date?

    public init(
        name: String, estimatedPrice: Money, priority: Priority = .medium, status: WishlistStatus = .wanted,
        categoryID: UUID? = nil, notes: String? = nil, targetDate: Date? = nil
    ) {
        self.name = name
        self.estimatedPrice = estimatedPrice
        self.priority = priority
        self.status = status
        self.categoryID = categoryID
        self.notes = notes
        self.targetDate = targetDate
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Checks that need no store access. Currency and category are checked by the service.
    public func validate() throws {
        guard !trimmedName.isEmpty else { throw WishlistError.emptyName }
        guard estimatedPrice.minorUnits >= 0 else { throw WishlistError.negativeEstimate }
        guard status == .wanted || status == .pending else { throw WishlistError.statusRequiresDedicatedPath(status) }
    }
}
