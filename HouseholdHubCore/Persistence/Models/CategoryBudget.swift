import Foundation
import SwiftData

extension SchemaV1 {
    /// A monthly spending limit on one expense category (owner decision 13, Sprint 11). With `rollsOver` on (the
    /// default, owner decision 17), what was left unspent adds to the next month and an overspend takes from it,
    /// counted from `startMonth`, the month the budget was created. A budget is not financial history: deleting its
    /// category removes it.
    @Model
    public final class CategoryBudget {
        @Attribute(.unique) public var id: UUID
        @Attribute(.unique) public var categoryID: UUID
        public var limitMinorUnits: Int64
        public var currencyCode: String
        public var rollsOver: Bool
        /// The first day of the month the budget starts counting from, in the household calendar.
        public var startMonth: Date
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), categoryID: UUID, limit: Money, rollsOver: Bool, startMonth: Date, now: Date
        ) {
            self.id = id
            self.categoryID = categoryID
            self.limitMinorUnits = limit.minorUnits
            self.currencyCode = limit.currencyCode
            self.rollsOver = rollsOver
            self.startMonth = startMonth
            self.createdAt = now
            self.updatedAt = now
        }

        public var limit: Money {
            Money(minorUnits: limitMinorUnits, currencyCode: currencyCode)
        }

        public var rule: BudgetRule {
            BudgetRule(categoryID: categoryID, limit: limit, rollsOver: rollsOver, startMonth: startMonth)
        }
    }
}

public typealias CategoryBudget = SchemaV1.CategoryBudget
