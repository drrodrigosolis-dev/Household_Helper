import HouseholdHubCore
import SwiftData
import SwiftUI

/// A parsed CSV file waiting for its preview (Sprint 15).
struct CSVImportSource: Identifiable {
    let id = UUID()
    let fileName: String
    let header: [String]
    /// Data records, header excluded, with their file lines.
    let records: [CSVRecord]

    func values(of column: Int?) -> [String] {
        guard let column else { return [] }
        return records.compactMap { $0.fields.indices.contains(column) ? $0.fields[column] : nil }
    }
}

/// CSV import preview (Sprint 15, owner decision 24): confirm which column is which, how dates and decimals are
/// written, whether spending is positive, and the account; then see every row: ready, likely duplicate (unticked), or
/// skipped with its file line and reason. Nothing is saved until Import, and then everything in one save. Where the
/// file is ambiguous (dates, decimal mark) the user must choose; nothing is guessed.
struct CSVImportView: View {
    let source: CSVImportSource
    let onImported: (Int) -> Void

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categoryRecords: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var columns: [CSVColumnRole: Int]
    @State private var dateFormat: CSVDateFormat?
    @State private var decimalMark: Character?
    @State private var spendingIsPositive = false
    @State private var accountID: UUID?
    @State private var existing: [CSVExistingTransaction]?
    @State private var existingFailed = false
    /// Bumped by each duplicate-check load, so the preview follows the latest one.
    @State private var loadGeneration = 0
    @State private var rows: [CSVPreviewRow] = []
    /// The user's own tick or untick per file line; rows without one follow the default (ready, not a duplicate).
    @State private var choices: [Int: Bool] = [:]
    @State private var isConfirming = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let calendar = HouseholdCalendar(timeZone: .current)

    init(source: CSVImportSource, onImported: @escaping (Int) -> Void) {
        self.source = source
        self.onImported = onImported
        let guessed = CSVMapping.guessColumns(header: source.header)
        _columns = State(initialValue: guessed)
        let calendar = HouseholdCalendar(timeZone: .current)
        let dates = CSVDateFormat.candidates(for: source.values(of: guessed[.date]), calendar: calendar)
        _dateFormat = State(initialValue: dates.count == 1 ? dates.first : nil)
        _decimalMark = State(initialValue: Self.initialDecimalMark(source.values(of: guessed[.amount])))
    }

    /// The column's own mark; "." when its values have no decimals at all; nil (the user picks) when a value like
    /// "1.234" could be read either way.
    private static func initialDecimalMark(_ values: [String]) -> Character? {
        if let detected = CSVAmount.detectDecimalMark(values) { return detected }
        let ambiguous = values.contains { value in
            let marks = value.filter { $0 == "." || $0 == "," }
            guard marks.count == 1, let mark = marks.first, let index = value.lastIndex(of: mark) else { return false }
            return value[value.index(after: index)...].prefix { $0.isNumber }.count == 3
        }
        return ambiguous ? nil : "."
    }

    private var currency: Currency? { try? Currency(code: settings.first?.currencyCode ?? "CAD") }

    private var chosenAccountID: UUID? {
        accountID ?? settings.first?.defaultAccountID ?? accounts.first { !$0.isArchived }?.id
    }

    private var dateChoices: [CSVDateFormat] {
        let fitting = CSVDateFormat.candidates(for: source.values(of: columns[.date]), calendar: calendar)
        return fitting.isEmpty ? CSVDateFormat.allCases : fitting
    }

    /// Everything the preview depends on; it is recomputed only when this changes.
    private var inputs: PreviewInputs {
        PreviewInputs(
            columns: columns, dateFormat: dateFormat, decimalMark: decimalMark, spendingIsPositive: spendingIsPositive,
            loadGeneration: existing == nil ? -1 : loadGeneration)
    }

    private func isIncluded(_ row: CSVPreviewRow) -> Bool {
        guard row.row != nil else { return false }
        return choices[row.line] ?? !row.isLikelyDuplicate
    }

    private var missingChoice: String? {
        if columns[.date] == nil || columns[.amount] == nil {
            return String(localized: "Choose the Date and Amount columns.")
        }
        if dateFormat == nil { return String(localized: "These dates can be read more than one way: choose how.") }
        if decimalMark == nil {
            return String(localized: "Amounts like 1.234 can be read more than one way: choose the decimal mark.")
        }
        if existingFailed { return String(localized: "Recorded transactions couldn't be checked for duplicates.") }
        return nil
    }

    var body: some View {
        let included = rows.filter(isIncluded)
        Form {
            columnsSection
            readingSection
            Section {
                if let missingChoice {
                    Text(missingChoice).foregroundStyle(.orange)
                        .accessibilityIdentifier("csv.needsChoice")
                } else if existing == nil {
                    ProgressView("Checking for duplicates…")
                } else {
                    Text(CSVImportFormat.summary(rows, included: included.count))
                        .accessibilityIdentifier("csv.summary")
                    ForEach(rows) { row in
                        previewRow(row)
                    }
                }
            } header: {
                Text("Preview")
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { isConfirming = true }
                    .disabled(
                        included.isEmpty || chosenAccountID == nil || missingChoice != nil || existing == nil
                            || isSaving)
                    .accessibilityIdentifier("csv.import")
            }
        }
        .confirmationDialog(
            "Import \(included.count) transactions?", isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button("Import \(included.count) transactions") { Task { await save(included) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They're added to \(accountName) and marked as imported. You can edit or delete them later.")
        }
        .task(id: LoadKey(account: chosenAccountID, dateColumn: columns[.date])) { await loadExisting() }
        .onChange(of: inputs, initial: true) { recompute() }
    }

    private var columnsSection: some View {
        Section {
            ForEach(CSVColumnRole.allCases, id: \.self) { role in
                Picker(CSVImportFormat.roleTitle(role), selection: columnBinding(role)) {
                    Text(role == .date || role == .amount ? "Choose" : "None").tag(Int?.none)
                    ForEach(source.header.indices, id: \.self) { index in
                        Text(CSVImportFormat.columnTitle(source.header[index], index: index)).tag(Int?.some(index))
                    }
                }
                .accessibilityIdentifier("csv.column.\(role.rawValue)")
            }
        } header: {
            Text("Columns in \(source.fileName)")
        } footer: {
            Text("Categories are matched by name; anything else is filed as Uncategorized.")
        }
    }

    private var readingSection: some View {
        Section {
            Picker("Dates look like", selection: $dateFormat) {
                Text("Choose").tag(CSVDateFormat?.none)
                ForEach(dateChoices, id: \.self) { format in
                    Text(CSVImportFormat.dateTitle(format)).tag(CSVDateFormat?.some(format))
                }
            }
            .accessibilityIdentifier("csv.dateFormat")
            Picker("Decimal mark", selection: $decimalMark) {
                Text("Choose").tag(Character?.none)
                Text("Point: 1,234.56").tag(Character?.some("."))
                Text("Comma: 1.234,56").tag(Character?.some(","))
            }
            .accessibilityIdentifier("csv.decimalMark")
            Toggle("Spending is positive", isOn: $spendingIsPositive)
                .accessibilityIdentifier("csv.spendingIsPositive")
            Picker("Account", selection: accountBinding) {
                ForEach(accounts.filter { !$0.isArchived }) { account in
                    Text(account.name).tag(UUID?.some(account.id))
                }
            }
            .accessibilityIdentifier("csv.account")
        } footer: {
            if spendingIsPositive {
                Text("Positive amounts are spending; negative amounts are income.")
            } else {
                Text("Negative amounts are spending; positive amounts are income.")
            }
        }
    }

    private var accountName: String {
        accounts.first { $0.id == chosenAccountID }?.name ?? ""
    }

    @ViewBuilder
    private func previewRow(_ row: CSVPreviewRow) -> some View {
        switch row.outcome {
        case .success(let entry):
            Toggle(isOn: includedBinding(row)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.description ?? String(localized: "No description"))
                    Text(CSVImportFormat.detail(entry, line: row.line, categories: categoryRecords))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.isLikelyDuplicate {
                        Label("Looks like one already recorded", systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .accessibilityIdentifier("csv.row")
        case .failure(let error):
            VStack(alignment: .leading, spacing: 2) {
                Text("Line \(row.line) skipped")
                Text(CSVImportFormat.reason(error.reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("csv.skipped")
        }
    }

    private func columnBinding(_ role: CSVColumnRole) -> Binding<Int?> {
        Binding(
            get: { columns[role] },
            set: { column in
                columns[role] = column
                // A new date column may read differently: choose again unless it's clear.
                if role == .date {
                    let fitting = CSVDateFormat.candidates(for: source.values(of: column), calendar: calendar)
                    dateFormat = fitting.count == 1 ? fitting.first : nil
                } else if role == .amount {
                    decimalMark = Self.initialDecimalMark(source.values(of: column))
                }
            })
    }

    private var accountBinding: Binding<UUID?> {
        Binding(get: { chosenAccountID }, set: { accountID = $0 })
    }

    private func includedBinding(_ row: CSVPreviewRow) -> Binding<Bool> {
        Binding(get: { isIncluded(row) }, set: { choices[row.line] = $0 })
    }

    private func recompute() {
        guard let currency, let dateFormat, let decimalMark, let existing, columns[.date] != nil,
            columns[.amount] != nil
        else {
            rows = []
            return
        }
        let categories = categoryRecords.filter { !$0.isArchived }.map {
            CSVImportCategory(id: $0.id, name: $0.name, kind: $0.kind)
        }
        let mapping = CSVMapping(
            columns: columns, dateFormat: dateFormat, decimalMark: decimalMark, spendingIsPositive: spendingIsPositive)
        rows = CSVImportPlanner.preview(
            records: source.records, headerCount: source.header.count, mapping: mapping, currency: currency,
            categories: categories, existing: existing, calendar: calendar)
    }

    /// Recorded transactions in the chosen account over the file's whole date span (any format that reads it).
    private func loadExisting() async {
        guard let services, let account = chosenAccountID else { return }
        existing = nil
        existingFailed = false
        let dates = CSVDateFormat.allCases.flatMap { format in
            source.values(of: columns[.date]).compactMap { format.date(from: $0, calendar: calendar) }
        }
        guard let from = dates.min(), let to = dates.max() else {
            existing = []
            loadGeneration += 1
            return
        }
        do {
            existing = try await services.transactions.existingForImport(
                accountID: account, from: from, to: to, calendar: calendar)
            loadGeneration += 1
        } catch {
            existingFailed = true
        }
    }

    private func save(_ rows: [CSVPreviewRow]) async {
        guard let services, let account = chosenAccountID, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let count = try await services.transactions.importTransactions(
                rows.compactMap(\.row), into: account, now: .now)
            onImported(count)
            dismiss()
        } catch LedgerError.archivedAccount, LedgerError.unknownAccount {
            errorMessage = String(localized: "Nothing was imported: that account can't take new transactions.")
        } catch LedgerError.archivedCategory, LedgerError.unknownCategory {
            errorMessage = String(localized: "Nothing was imported: a category changed meanwhile. Try again.")
        } catch {
            errorMessage = String(localized: "Nothing was imported: a row couldn't be saved. Your data is unchanged.")
        }
    }
}

/// What the duplicate check depends on.
private struct LoadKey: Equatable {
    let account: UUID?
    let dateColumn: Int?
}

/// What the preview depends on, compared to recompute it only when something changed.
private struct PreviewInputs: Equatable {
    let columns: [CSVColumnRole: Int]
    let dateFormat: CSVDateFormat?
    let decimalMark: Character?
    let spendingIsPositive: Bool
    let loadGeneration: Int
}

/// Wording for the import preview.
enum CSVImportFormat {
    static func roleTitle(_ role: CSVColumnRole) -> LocalizedStringKey {
        switch role {
        case .date: return "Date"
        case .amount: return "Amount"
        case .description: return "Description"
        case .category: return "Category"
        }
    }

    static func columnTitle(_ header: String, index: Int) -> String {
        let name = header.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "Column \(index + 1)") : name
    }

    static func dateTitle(_ format: CSVDateFormat) -> String {
        switch format {
        case .yearMonthDay: return String(localized: "2026-09-25 (year first)")
        case .monthDayYear: return String(localized: "09/25/2026 (month first)")
        case .dayMonthYear: return String(localized: "25/09/2026 (day first)")
        }
    }

    static func summary(_ rows: [CSVPreviewRow], included: Int) -> String {
        let duplicates = rows.filter(\.isLikelyDuplicate).count
        let skipped = rows.filter { $0.row == nil }.count
        return String(localized: "\(included) to import · \(duplicates) likely duplicates · \(skipped) skipped")
    }

    static func detail(_ row: CSVImportRow, line: Int, categories: [CategoryRecord]) -> String {
        let date = row.occurredAt.formatted(date: .abbreviated, time: .omitted)
        let amount = LedgerFormat.signedAmount(row.amount, type: row.type)
        let category = categories.first { $0.id == row.categoryID }?.name ?? String(localized: "Uncategorized")
        return "\(date) · \(amount) · \(category) · " + String(localized: "line \(line)")
    }

    static func reason(_ reason: CSVSkipReason) -> String {
        switch reason {
        case .columnCount(let expected, let found):
            return String(localized: "Has \(found) fields where the header has \(expected); a stray separator?")
        case .missingDate: return String(localized: "No date.")
        case .unreadableDate(let text): return String(localized: "“\(text)” isn't a date in the chosen format.")
        case .missingAmount: return String(localized: "No amount.")
        case .unreadableAmount(let text):
            return String(localized: "“\(text)” can't be read as an amount without guessing.")
        case .zeroAmount: return String(localized: "The amount is zero.")
        case .amountTooLarge(let text): return String(localized: "“\(text)” is too large to be an amount.")
        }
    }
}
