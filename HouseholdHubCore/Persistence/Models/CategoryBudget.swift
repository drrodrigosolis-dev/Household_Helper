import Foundation
import SwiftData

extension SchemaV1 {
    /// A monthly spending limit on one expense category (owner decision 13, Sprint 11). With `rollsOver` on (the
    /// default, owner decision 17), what was left unspent adds to the next month and an overspend takes from it,
    /// counted from the start month (the month the budget was created, or rollover last turned on). A budget is not
    /// financial history: deleting its category removes it.
    ///
    /// One budget per category is kept by `CategoryService` and the backup validator, deliberately not by a
    /// `.unique` attribute: a unique clash makes SwiftData upsert, which a restore's merge-by-id must never meet
    /// (`docs/research/apple-api-decisions.md`).
    @Model
    public final class CategoryBudget {
        @Attribute(.unique) public var id: UUID
        public var categoryID: UUID
        public var limitMinorUnits: Int64
        public var currencyCode: String
        public var rollsOver: Bool
        /// The month counting starts from, as calendar numbers rather than an instant, so moving the device to
        /// another time zone can't shift it into the previous month.
        public var startYear: Int
        public var startMonthOfYear: Int
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), categoryID: UUID, limit: Money, rollsOver: Bool, start: BudgetMonth, now: Date
        ) {
            self.id = id
            self.categoryID = categoryID
            self.limitMinorUnits = limit.minorUnits
            self.currencyCode = limit.currencyCode
            self.rollsOver = rollsOver
            self.startYear = start.year
            self.startMonthOfYear = start.month
            self.createdAt = now
            self.updatedAt = now
        }

        public var start: BudgetMonth {
            get { BudgetMonth(year: startYear, month: startMonthOfYear) }
            set {
                startYear = newValue.year
                startMonthOfYear = newValue.month
            }
        }

        public var limit: Money {
            Money(minorUnits: limitMinorUnits, currencyCode: currencyCode)
        }

        public var rule: BudgetRule {
            BudgetRule(categoryID: categoryID, limit: limit, rollsOver: rollsOver, start: start)
        }
    }
}

public typealias CategoryBudget = SchemaV1.CategoryBudget
