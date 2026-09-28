import Foundation

/// A category the importer may file rows under (active ones only).
public struct CSVImportCategory: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: CategoryKind

    public init(id: UUID, name: String, kind: CategoryKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// A transaction already in the store, as duplicate detection needs it.
public struct CSVExistingTransaction: Equatable, Sendable {
    public let occurredAt: Date
    public let amount: Money
    public let type: TransactionType
    public let text: String?

    public init(occurredAt: Date, amount: Money, type: TransactionType, text: String?) {
        self.occurredAt = occurredAt
        self.amount = amount
        self.type = type
        self.text = text
    }
}

/// One row ready to import: an expense or income (never a transfer, decision 3) with a positive amount.
public struct CSVImportRow: Equatable, Sendable {
    public let occurredAt: Date
    public let amount: Money
    public let type: TransactionType
    public let description: String?
    /// nil = Uncategorized: the file's category matched no active category allowing this type (decision 5).
    public let categoryID: UUID?

    /// The same row filed under `categoryID`: the category the user settled on in the preview (Sprint 23).
    public func filed(under categoryID: UUID?) -> CSVImportRow {
        CSVImportRow(
            occurredAt: occurredAt, amount: amount, type: type, description: description, categoryID: categoryID)
    }
}

public enum CSVSkipReason: Equatable, Sendable {
    /// More or fewer fields than the header: a stray separator would shift values into the wrong columns.
    case columnCount(expected: Int, found: Int)
    case missingDate
    case unreadableDate(String)
    case missingAmount
    case unreadableAmount(String)
    case zeroAmount
    /// Above `Money.maxPlanMinorUnits`: most likely a reference or balance column, not an amount.
    case amountTooLarge(String)
}

/// A data row of the file and what the import would do with it (decision 4).
public struct CSVPreviewRow: Equatable, Sendable, Identifiable {
    /// 1-based line in the file, header included, so messages match what a spreadsheet shows.
    public let line: Int
    public let outcome: Result<CSVImportRow, CSVSkipError>
    /// Same day, amount, type and description as a transaction already recorded: unticked by default.
    public let isLikelyDuplicate: Bool
    /// For a row the file left uncategorized: the category its merchant was last filed under by hand (Sprint 23,
    /// A-006), active and allowing the row's type. Only offered: the row itself keeps the file's category.
    public let suggestedCategoryID: UUID?

    public var id: Int { line }
    public var row: CSVImportRow? { try? outcome.get() }
}

public struct CSVSkipError: Error, Equatable, Sendable {
    public let reason: CSVSkipReason
}

/// Deterministic preview (Sprint 15): reads each data row with the mapping; nothing is written.
public enum CSVImportPlanner {
    /// - Parameters:
    ///   - records: the data records (header excluded), with their file lines.
    ///   - headerCount: how many fields the header has; rows with a different count are skipped.
    ///   - suggestions: learned categories keyed by `Merchant.normalize(_:)` of a description
    ///     (`TransactionService.importCategorySuggestions(for:)`), offered for rows the file left uncategorized.
    public static func preview(
        records: [CSVRecord], headerCount: Int, mapping: CSVMapping, currency: Currency,
        categories: [CSVImportCategory], existing: [CSVExistingTransaction], suggestions: [String: UUID] = [:],
        calendar: HouseholdCalendar
    ) -> [CSVPreviewRow] {
        let known = Set(existing.map { key($0.occurredAt, $0.amount.minorUnits, $0.type, $0.text, calendar) })
        return records.map { record in
            let line = record.line
            // Trailing empty fields (a trailing separator some banks write) don't count.
            var fields = record.fields
            while fields.count > headerCount, fields.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                fields.removeLast()
            }
            guard fields.count == headerCount else {
                let reason = CSVSkipReason.columnCount(expected: headerCount, found: fields.count)
                let skipped = CSVSkipError(reason: reason)
                return CSVPreviewRow(
                    line: line, outcome: .failure(skipped), isLikelyDuplicate: false, suggestedCategoryID: nil)
            }
            switch read(fields, mapping: mapping, currency: currency, categories: categories, calendar: calendar) {
            case .success(let row):
                let duplicate = known.contains(
                    key(row.occurredAt, row.amount.minorUnits, row.type, row.description, calendar))
                return CSVPreviewRow(
                    line: line, outcome: .success(row), isLikelyDuplicate: duplicate,
                    suggestedCategoryID: suggestion(for: row, in: suggestions, categories: categories))
            case .failure(let error):
                return CSVPreviewRow(
                    line: line, outcome: .failure(error), isLikelyDuplicate: false, suggestedCategoryID: nil)
            }
        }
    }

    /// The learned category for a row without one from the file, if it is still offered (active) and allows the row.
    private static func suggestion(
        for row: CSVImportRow, in suggestions: [String: UUID], categories: [CSVImportCategory]
    ) -> UUID? {
        guard row.categoryID == nil, let description = row.description,
            let id = suggestions[Merchant.normalize(description)]
        else { return nil }
        return categories.first { $0.id == id && $0.kind.allows(row.type) }?.id
    }

    static func read(
        _ fields: [String], mapping: CSVMapping, currency: Currency, categories: [CSVImportCategory],
        calendar: HouseholdCalendar
    ) -> Result<CSVImportRow, CSVSkipError> {
        func value(_ role: CSVColumnRole) -> String? {
            guard let index = mapping.columns[role], fields.indices.contains(index) else { return nil }
            let text = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        guard let dateText = value(.date) else { return .failure(CSVSkipError(reason: .missingDate)) }
        guard let date = mapping.dateFormat.date(from: dateText, calendar: calendar) else {
            return .failure(CSVSkipError(reason: .unreadableDate(dateText)))
        }
        guard let amountText = value(.amount) else { return .failure(CSVSkipError(reason: .missingAmount)) }
        guard let signed = CSVAmount.signedMinorUnits(amountText, currency: currency, decimalMark: mapping.decimalMark)
        else { return .failure(CSVSkipError(reason: .unreadableAmount(amountText))) }
        guard signed != 0 else { return .failure(CSVSkipError(reason: .zeroAmount)) }
        guard abs(signed) <= Money.maxPlanMinorUnits else {
            return .failure(CSVSkipError(reason: .amountTooLarge(amountText)))
        }
        let isSpending = mapping.spendingIsPositive ? signed > 0 : signed < 0
        let type: TransactionType = isSpending ? .expense : .income
        let categoryName = value(.category).map(fold)
        let category = categoryName.flatMap { name in
            categories.first { fold($0.name) == name && $0.kind.allows(type) }?.id
        }
        return .success(
            CSVImportRow(
                occurredAt: date, amount: Money(minorUnits: abs(signed), currencyCode: currency.code), type: type,
                description: value(.description), categoryID: category))
    }

    private static func key(
        _ date: Date, _ minorUnits: Int64, _ type: TransactionType, _ text: String?, _ calendar: HouseholdCalendar
    ) -> String {
        let day = calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
        return "\(day)|\(minorUnits)|\(type.rawValue)|\(fold(text ?? ""))"
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
