import Foundation
import SwiftData

extension TransactionService {
    /// Every active category's budget for the month containing `month` (Sprint 11): posted expenses count, pending
    /// ones only while Analytics' "Include pending" is on, cancelled ones and transfers never. Budgets of archived
    /// categories are left out.
    public func budgetReport(month: Date, calendar: HouseholdCalendar) throws -> [BudgetStatus] {
        let settings = try requireSettings()
        let categories = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
        let active = Set(categories.filter { !$0.isArchived }.map(\.id))
        let rules = try modelContext.fetch(FetchDescriptor<CategoryBudget>()).map(\.rule)
            .filter { active.contains($0.categoryID) }
        guard let earliest = rules.map(\.startMonth).min() else { return [] }
        let budgeted = Set(rules.map(\.categoryID))
        let expense = TransactionType.expense.rawValue
        let posted = TransactionStatus.posted.rawValue
        let pending = TransactionStatus.pending.rawValue
        let withPending = settings.analyticsIncludesPending
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                $0.typeRawValue == expense && $0.occurredAt >= earliest
                    && ($0.statusRawValue == posted || (withPending && $0.statusRawValue == pending))
            })
        let lines = try modelContext.fetch(descriptor).compactMap { record -> BudgetLine? in
            guard let categoryID = record.categoryID, budgeted.contains(categoryID) else { return nil }
            let amount = try record.ledgerLine().amount
            return BudgetLine(categoryID: categoryID, amount: amount, occurredAt: record.occurredAt)
        }
        return try BudgetCalculator().statuses(rules, lines: lines, month: month, calendar: calendar)
    }
}
