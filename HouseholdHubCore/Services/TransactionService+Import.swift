import Foundation
import SwiftData

/// CSV import (Sprint 15, owner decision 24): the rows the user kept in the preview, into one account, in one save.
extension TransactionService {
    /// Transactions in `accountID` dated between `from` and `to` (inclusive days), for the preview's duplicate check.
    /// Cancelled ones don't count: a bank row matching a cancelled entry is a real transaction.
    public func existingForImport(
        accountID: UUID, from: Date, to: Date, calendar: HouseholdCalendar
    ) throws -> [CSVExistingTransaction] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.endOfDay(for: to)
        let account: UUID? = accountID
        let cancelled = TransactionStatus.cancelled.rawValue
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.occurredAt >= start && $0.occurredAt < end && $0.accountID == account })
        let live = try modelContext.fetch(descriptor).filter { $0.statusRawValue != cancelled }
        return live.flatMap { record -> [CSVExistingTransaction] in
            // A bank lists a refund as money in, which the import reads as income (Sprint 20): matched as such, so
            // a refund already recorded here is flagged as a likely duplicate.
            let type: TransactionType = record.type == .refund ? .income : record.type
            // Imports keep the file's description as the merchant (Sprint 23, A-003); earlier ones kept it in the
            // notes, and an entry typed in may have both: a bank row matching either is a likely duplicate.
            var texts = [record.merchantNameSnapshot ?? record.notes]
            if let notes = record.notes, let merchant = record.merchantNameSnapshot, notes != merchant {
                texts.append(notes)
            }
            return texts.map { text in
                CSVExistingTransaction(occurredAt: record.occurredAt, amount: record.amount, type: type, text: text)
            }
        }
    }

    /// The category each merchant named in `descriptions` was last filed under by hand (Sprint 23, A-006), keyed by
    /// `Merchant.normalize(_:)`; names without one, and archived categories, are left out. The preview offers these
    /// as suggestions; nothing here applies them. One fetch of merchants and one of categories for the whole file.
    public func importCategorySuggestions(for descriptions: [String]) throws -> [String: UUID] {
        let keys = Set(descriptions.map { Merchant.normalize($0) }.filter { !$0.isEmpty })
        guard !keys.isEmpty else { return [:] }
        let active = Set(try modelContext.fetch(FetchDescriptor<CategoryRecord>()).filter { !$0.isArchived }.map(\.id))
        let merchants = try modelContext.fetch(FetchDescriptor<Merchant>(sortBy: [SortDescriptor(\.createdAt)]))
        var suggestions: [String: UUID] = [:]
        for merchant in merchants where keys.contains(merchant.normalizedName) {
            // Names aren't unique; the oldest merchant with a usable category speaks for the name.
            guard suggestions[merchant.normalizedName] == nil, let category = merchant.defaultCategoryID,
                active.contains(category)
            else { continue }
            suggestions[merchant.normalizedName] = category
        }
        return suggestions
    }

    /// Records every row as a posted transaction with source `imported`, all or nothing: any refusal (an archived or
    /// unknown account or category, a currency mismatch, too many rows) leaves the store unchanged. Returns the count.
    /// Each row's description becomes its merchant (found or made once per name, Sprint 23), never its notes; the
    /// merchants' learned categories are left as they are.
    @discardableResult
    public func importTransactions(_ rows: [CSVImportRow], into accountID: UUID, now: Date) throws -> Int {
        begin()
        guard rows.count <= CSVParser.maximumRows else { throw CSVParser.Failure.tooManyRows(CSVParser.maximumRows) }
        let settings = try requireSettings()
        try requireUsableAccount(accountID)
        for row in rows {
            let draft = TransactionDraft(
                amount: row.amount, type: row.type, occurredAt: row.occurredAt, categoryID: row.categoryID,
                merchantName: row.description, source: .imported, accountID: accountID)
            try draft.validate()
            guard row.amount.minorUnits <= Money.maxPlanMinorUnits else { throw LedgerError.amountTooLarge }
            try requireCurrency(row.amount, settings)
            if let categoryID = row.categoryID {
                try requireUsableCategory(categoryID, for: row.type)
            }
        }
        do {
            var merchants: [String: Merchant] = [:]
            for row in rows {
                let record = TransactionRecord(
                    amount: row.amount, type: row.type, status: .posted, source: .imported, occurredAt: row.occurredAt,
                    now: now)
                record.accountID = accountID
                record.categoryID = row.categoryID
                let name = row.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let key = Merchant.normalize(name)
                if !key.isEmpty {
                    let merchant = try merchants[key] ?? findOrCreateMerchant(named: name, now: now)
                    merchants[key] = merchant
                    record.merchantID = merchant.id
                    record.merchantNameSnapshot = name
                }
                modelContext.insert(record)
            }
        } catch {
            // A failed merchant lookup mid-way leaves nothing pending: the import is all or nothing.
            modelContext.rollback()
            throw error
        }
        try commit()
        return rows.count
    }
}
