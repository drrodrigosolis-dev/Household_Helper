import Foundation
import SwiftData

/// CSV import (Sprint 15, owner decision 24): the rows the user kept in the preview, into one account, in one save.
extension TransactionService {
    /// Transactions dated between `from` and `to` (inclusive days), for the preview's duplicate check.
    public func existingForImport(
        from: Date, to: Date, calendar: HouseholdCalendar
    ) throws -> [CSVExistingTransaction] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.endOfDay(for: to)
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end })
        return try modelContext.fetch(descriptor).map { record in
            CSVExistingTransaction(
                occurredAt: record.occurredAt, amount: record.amount, type: record.type,
                text: record.notes ?? record.merchantNameSnapshot)
        }
    }

    /// Records every row as a posted transaction with source `imported`, all or nothing: any refusal (an archived or
    /// unknown account or category, a currency mismatch, too many rows) leaves the store unchanged. Returns the count.
    @discardableResult
    public func importTransactions(_ rows: [CSVImportRow], into accountID: UUID, now: Date) throws -> Int {
        begin()
        guard rows.count <= CSVParser.maximumRows else { throw CSVParser.Failure.tooManyRows(CSVParser.maximumRows) }
        let settings = try requireSettings()
        try requireUsableAccount(accountID)
        for row in rows {
            let draft = TransactionDraft(
                amount: row.amount, type: row.type, occurredAt: row.occurredAt, categoryID: row.categoryID,
                notes: row.description, source: .imported, accountID: accountID)
            try draft.validate()
            try requireCurrency(row.amount, settings)
            if let categoryID = row.categoryID {
                try requireUsableCategory(categoryID, for: row.type)
            }
        }
        for row in rows {
            let record = TransactionRecord(
                amount: row.amount, type: row.type, status: .posted, source: .imported, occurredAt: row.occurredAt,
                now: now)
            record.accountID = accountID
            record.categoryID = row.categoryID
            record.notes = row.description
            modelContext.insert(record)
        }
        try commit()
        return rows.count
    }
}
