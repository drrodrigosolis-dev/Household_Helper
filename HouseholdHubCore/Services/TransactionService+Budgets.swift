import Foundation
import SwiftData

extension TransactionService {
    /// Every active category's budget for the month containing `month` (Sprint 11): posted expenses count, pending
    /// ones only while Analytics' "Include pending" is on, cancelled ones and transfers never. Refunds count against
    /// spending in their own month (Sprint 20). Budgets of archived categories are left out.
    ///
    /// Any month can be reported (Sprint 23, A-017: Budgets' month history). Every budget is read with its current
    /// limit and rollover setting: a month before its start month shows that month's spending against the limit with
    /// nothing carried, and rollover builds up from the start month to the month reported.
    public func budgetReport(month: Date, calendar: HouseholdCalendar) throws -> [BudgetStatus] {
        let settings = try requireSettings()
        let categories = try modelContext.fetch(FetchDescriptor<CategoryRecord>())
        let active = Set(categories.filter { !$0.isArchived }.map(\.id))
        let rules = try modelContext.fetch(FetchDescriptor<CategoryBudget>()).map(\.rule)
            .filter { active.contains($0.categoryID) }
        guard let first = rules.map(\.start).min() else { return [] }
        // Spending from the earliest start (rollover chains), or from the reported month when that is earlier.
        let earliest = min(first, BudgetMonth(containing: month, calendar: calendar)).start(in: calendar)
        let budgeted = Set(rules.map(\.categoryID))
        let expense = TransactionType.expense.rawValue
        let refund = TransactionType.refund.rawValue
        let posted = TransactionStatus.posted.rawValue
        let pending = TransactionStatus.pending.rawValue
        let withPending = settings.analyticsIncludesPending
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                ($0.typeRawValue == expense || $0.typeRawValue == refund) && $0.occurredAt >= earliest
                    && ($0.statusRawValue == posted || (withPending && $0.statusRawValue == pending))
            })
        let lines = try modelContext.fetch(descriptor).compactMap { record -> BudgetLine? in
            guard let categoryID = record.categoryID, budgeted.contains(categoryID) else { return nil }
            let line = try record.ledgerLine()
            let amount = line.type == .refund ? try line.amount.negated() : line.amount
            return BudgetLine(categoryID: categoryID, amount: amount, occurredAt: record.occurredAt)
        }
        return try BudgetCalculator().statuses(rules, lines: lines, month: month, calendar: calendar)
    }
}
