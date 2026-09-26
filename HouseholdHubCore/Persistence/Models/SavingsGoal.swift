import Foundation
import SwiftData

extension SchemaV1 {
    /// Something the household is saving towards (owner decision 19, Sprint 12). Progress is one account's current
    /// balance, never money set aside inside the app: a goal records no transactions and moves nothing. Two goals on
    /// the same account show the same balance.
    ///
    /// A goal is not financial history. While it exists, its account and wishlist item can't be deleted (they can
    /// still be archived); deleting the goal leaves both untouched.
    @Model
    public final class SavingsGoal {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var targetMinorUnits: Int64
        public var currencyCode: String
        public var accountID: UUID
        /// The day to reach the target by, if any; only its calendar day counts.
        public var targetDate: Date?
        /// At most one goal per wishlist item, kept by `TransactionService` and the backup validator.
        public var wishlistItemID: UUID?
        public var isArchived: Bool
        public var sortOrder: Int
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), name: String, target: Money, accountID: UUID, targetDate: Date?,
            wishlistItemID: UUID?, sortOrder: Int, now: Date
        ) {
            self.id = id
            self.name = name
            self.targetMinorUnits = target.minorUnits
            self.currencyCode = target.currencyCode
            self.accountID = accountID
            self.targetDate = targetDate
            self.wishlistItemID = wishlistItemID
            self.isArchived = false
            self.sortOrder = sortOrder
            self.createdAt = now
            self.updatedAt = now
        }

        public var target: Money {
            Money(minorUnits: targetMinorUnits, currencyCode: currencyCode)
        }

        public var rule: GoalRule {
            GoalRule(
                id: id, name: name, target: target, accountID: accountID, targetDate: targetDate,
                wishlistItemID: wishlistItemID, isArchived: isArchived)
        }
    }
}

public typealias SavingsGoal = SchemaV1.SavingsGoal
