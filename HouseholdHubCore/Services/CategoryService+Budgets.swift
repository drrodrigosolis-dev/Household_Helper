import Foundation
import SwiftData

/// Category budgets (Sprint 11). Written only here, next to the categories they belong to, so deleting or re-kinding
/// a category and changing its budget can't race.
extension CategoryService {
    /// Sets a category's monthly limit, creating the budget if there is none. A new budget starts counting (and
    /// rolling over) from the month of `now`; editing one keeps its start.
    public func setBudget(
        for categoryID: UUID, limit: Money, rollsOver: Bool, currencyCode: String, now: Date,
        calendar: HouseholdCalendar
    ) throws {
        begin()
        guard limit.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        guard limit.currencyCode == currencyCode else {
            throw LedgerError.currencyMismatch(expected: currencyCode, actual: limit.currencyCode)
        }
        let category = try requireCategory(categoryID)
        guard category.kind.allows(.expense) else { throw LedgerError.categoryKindMismatch(category.kind, .expense) }
        if let existing = try budget(of: categoryID) {
            existing.limitMinorUnits = limit.minorUnits
            existing.currencyCode = limit.currencyCode
            existing.rollsOver = rollsOver
            existing.updatedAt = now
        } else {
            guard !category.isArchived else { throw LedgerError.archivedCategory }
            modelContext.insert(
                CategoryBudget(
                    categoryID: categoryID, limit: limit, rollsOver: rollsOver,
                    startMonth: calendar.startOfMonth(for: now), now: now))
        }
        try commit()
    }

    public func removeBudget(for categoryID: UUID) throws {
        begin()
        try deleteBudget(of: categoryID)
        try commit()
    }

    /// Deletes the category's budget, if any, without saving.
    func deleteBudget(of categoryID: UUID) throws {
        if let existing = try budget(of: categoryID) {
            modelContext.delete(existing)
        }
    }

    private func budget(of categoryID: UUID) throws -> CategoryBudget? {
        try modelContext.fetch(FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.categoryID == categoryID }))
            .first
    }
}
