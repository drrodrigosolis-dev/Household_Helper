import Foundation
import SwiftData

extension TransactionService {
    /// How far back recurring detection looks: a year of monthly history, and then some.
    static let detectionLookbackDays = 400

    /// Recurring patterns in posted history that no series covers yet (Sprint 23 F2). Read-only: the Recurring
    /// screen offers each one, and only the recurring editor creates a series.
    public func recurringSuggestions(now: Date, calendar: HouseholdCalendar) throws -> [RecurringSuggestion] {
        let today = calendar.startOfDay(for: now)
        let back = -Self.detectionLookbackDays
        let earliest = calendar.calendar.date(byAdding: .day, value: back, to: today) ?? .distantPast
        let expense = TransactionType.expense.rawValue
        let income = TransactionType.income.rawValue
        let posted = TransactionStatus.posted.rawValue
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate {
                ($0.typeRawValue == expense || $0.typeRawValue == income) && $0.statusRawValue == posted
                    && $0.recurringSeriesID == nil && $0.occurredAt >= earliest
            })
        let records = try modelContext.fetch(descriptor)
        guard !records.isEmpty else { return [] }
        let allSeries = try modelContext.fetch(FetchDescriptor<RecurringTransaction>())
        var names: [UUID: String] = [:]
        for merchant in try modelContext.fetch(FetchDescriptor<Merchant>()) {
            names[merchant.id] = merchant.displayName
        }
        let history = records.map { record in
            RecurringHistoryItem(
                id: record.id, amount: record.amount, type: record.type, status: record.status,
                occurredAt: record.occurredAt, merchantID: record.merchantID,
                merchantName: record.merchantID.flatMap { names[$0] } ?? record.merchantNameSnapshot,
                notes: record.notes, categoryID: record.categoryID, accountID: record.accountID,
                recurringSeriesID: record.recurringSeriesID)
        }
        // Disabled series count too: turning one off is a choice, not a reason to suggest it again.
        let existing = allSeries.map { series in
            ExistingSeriesKey(
                type: series.type, merchantID: series.merchantID,
                names: [series.notes, series.merchantID.flatMap { names[$0] }].compactMap { $0 })
        }
        return RecurringDetector().suggestions(from: history, existing: existing, now: now, calendar: calendar)
    }

    /// This month's budgets with their category names, for budget alerts (Sprint 23 F7). The same figures as
    /// `budgetReport`, so an alert never disagrees with the Budgets screen.
    public func budgetAlertSources(month: Date, calendar: HouseholdCalendar) throws -> [BudgetAlertSource] {
        let statuses = try budgetReport(month: month, calendar: calendar)
        guard !statuses.isEmpty else { return [] }
        var names: [UUID: String] = [:]
        for category in try modelContext.fetch(FetchDescriptor<CategoryRecord>()) {
            names[category.id] = category.name
        }
        return statuses.map { BudgetAlertSource($0, categoryName: names[$0.categoryID] ?? "") }
    }
}
