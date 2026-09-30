import Foundation
import SwiftData

/// Category budgets (Sprint 11). Written only here, next to the categories they belong to, so deleting or re-kinding
/// a category and changing its budget can't race.
extension CategoryService {
    /// Sets a category's monthly limit in the household currency, creating the budget if there is none. A new budget
    /// starts counting (and rolling over) from the month of `now`; editing keeps its start, except that turning
    /// rollover back on starts it afresh this month, so months it was off never add carry.
    public func setBudget(
        for categoryID: UUID, limit: Money, rollsOver: Bool, now: Date, calendar: HouseholdCalendar
    ) throws {
        begin()
        guard limit.minorUnits > 0 else { throw LedgerError.nonPositiveAmount }
        guard limit.minorUnits <= Money.maxPlanMinorUnits else { throw LedgerError.amountTooLarge }
        var settingsDescriptor = FetchDescriptor<AppSettings>(sortBy: [SortDescriptor(\.createdAt)])
        settingsDescriptor.fetchLimit = 1
        guard let settings = try modelContext.fetch(settingsDescriptor).first else { throw LedgerError.settingsMissing }
        guard limit.currencyCode == settings.currencyCode else {
            throw LedgerError.currencyMismatch(expected: settings.currencyCode, actual: limit.currencyCode)
        }
        let category = try requireCategory(categoryID)
        guard category.kind.allows(.expense) else { throw LedgerError.categoryKindMismatch(category.kind, .expense) }
        guard !category.isArchived else { throw LedgerError.archivedCategory }
        let thisMonth = BudgetMonth(containing: now, calendar: calendar)
        if let existing = try budget(of: categoryID) {
            if rollsOver, !existing.rollsOver {
                existing.start = thisMonth
            }
            existing.limitMinorUnits = limit.minorUnits
            existing.currencyCode = limit.currencyCode
            existing.rollsOver = rollsOver
            existing.updatedAt = now
        } else {
            modelContext.insert(
                CategoryBudget(categoryID: categoryID, limit: limit, rollsOver: rollsOver, start: thisMonth, now: now))
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
        let descriptor = FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.categoryID == categoryID })
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
    }

    private func budget(of categoryID: UUID) throws -> CategoryBudget? {
        try modelContext.fetch(FetchDescriptor<CategoryBudget>(predicate: #Predicate { $0.categoryID == categoryID }))
            .first
    }
}
