import HouseholdHubCore
import SwiftData
import SwiftUI

/// A parsed CSV file waiting for its preview (Sprint 15).
struct CSVImportSource: Identifiable {
    let id = UUID()
    let fileName: String
    /// Header first.
    let rows: [[String]]

    var header: [String] { rows.first ?? [] }
    var dataRows: [[String]] { Array(rows.dropFirst()) }
}

/// CSV import preview (Sprint 15, owner decision 24): confirm which column is which, how dates are written, whether
/// spending is positive, and the account; then see every row: ready, likely duplicate (unticked), or skipped with the
/// reason. Nothing is saved until Import, and then everything in one save.
struct CSVImportView: View {
    let source: CSVImportSource
    let onImported: (Int) -> Void

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categoryRecords: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var columns: [CSVColumnRole: Int]
    @State private var dateFormat: CSVDateFormat
    @State private var spendingIsPositive = false
    @State private var accountID: UUID?
    @State private var existing: [CSVExistingTransaction] = []
    /// Lines the user unticked or ticked, over the default (ready rows ticked, likely duplicates not).
    @State private var toggled: Set<Int> = []
    @State private var isConfirming = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let calendar = HouseholdCalendar(timeZone: .current)
    /// Rows listed on screen; the rest still import and count in the summary.
    private static let listedRows = 300

    init(source: CSVImportSource, onImported: @escaping (Int) -> Void) {
        self.source = source
        self.onImported = onImported
        let guessed = CSVMapping.guessColumns(header: source.header)
        _columns = State(initialValue: guessed)
        let dates = guessed[.date].map { index in
            source.dataRows.compactMap { $0.indices.contains(index) ? $0[index] : nil }
        }
        let candidates = CSVDateFormat.candidates(for: dates ?? [], calendar: HouseholdCalendar(timeZone: .current))
        _dateFormat = State(initialValue: candidates.first ?? .yearMonthDay)
    }

    private var currency: Currency? {
        (try? Currency(code: settings.first?.currencyCode ?? "CAD"))
    }

    private var mapping: CSVMapping {
        CSVMapping(columns: columns, dateFormat: dateFormat, spendingIsPositive: spendingIsPositive)
    }

    private var categories: [CSVImportCategory] {
        categoryRecords.filter { !$0.isArchived }.map { CSVImportCategory(id: $0.id, name: $0.name, kind: $0.kind) }
    }

    private var preview: [CSVPreviewRow] {
        guard let currency, columns[.date] != nil, columns[.amount] != nil else { return [] }
        return CSVImportPlanner.preview(
            dataRows: source.dataRows, mapping: mapping, currency: currency, categories: categories,
            existing: existing, calendar: calendar)
    }

    private func isIncluded(_ row: CSVPreviewRow) -> Bool {
        guard row.row != nil else { return false }
        return row.isLikelyDuplicate == toggled.contains(row.line)
    }

    /// Date formats the date column reads as; more than one means the file is ambiguous and the user decides.
    private var dateChoices: [CSVDateFormat] {
        guard let index = columns[.date] else { return CSVDateFormat.allCases }
        let values = source.dataRows.compactMap { $0.indices.contains(index) ? $0[index] : nil }
        let fitting = CSVDateFormat.candidates(for: values, calendar: calendar)
        return fitting.isEmpty ? CSVDateFormat.allCases : fitting
    }

    private var chosenAccountID: UUID? {
        accountID ?? settings.first?.defaultAccountID ?? accounts.first { !$0.isArchived }?.id
    }

    var body: some View {
        let rows = preview
        let included = rows.filter(isIncluded)
        Form {
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
            Section {
                Picker("Dates look like", selection: $dateFormat) {
                    ForEach(dateChoices, id: \.self) { format in
                        Text(CSVImportFormat.dateTitle(format)).tag(format)
                    }
                }
                .accessibilityIdentifier("csv.dateFormat")
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
            Section {
                Text(CSVImportFormat.summary(rows, included: included.count))
                    .accessibilityIdentifier("csv.summary")
                ForEach(rows.prefix(Self.listedRows)) { row in
                    previewRow(row)
                }
                if rows.count > Self.listedRows {
                    Text("\(rows.count - Self.listedRows) more rows aren't listed; they follow the same rules.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    .disabled(included.isEmpty || chosenAccountID == nil || isSaving)
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
        .task { await loadExisting() }
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
        Binding(get: { columns[role] }, set: { columns[role] = $0 })
    }

    private var accountBinding: Binding<UUID?> {
        Binding(get: { chosenAccountID }, set: { accountID = $0 })
    }

    private func includedBinding(_ row: CSVPreviewRow) -> Binding<Bool> {
        Binding(
            get: { isIncluded(row) },
            set: { _ in
                if toggled.contains(row.line) {
                    toggled.remove(row.line)
                } else {
                    toggled.insert(row.line)
                }
            })
    }

    private func loadExisting() async {
        guard let services else { return }
        existing =
            (try? await services.transactions.existingForImport(
                from: .distantPast, to: .now.addingTimeInterval(10 * 365 * 86_400), calendar: calendar)) ?? []
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
        } catch {
            errorMessage = String(localized: "Nothing was imported: a row couldn't be saved. Your data is unchanged.")
        }
    }
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
        return String(
            localized: "\(included) to import · \(duplicates) likely duplicates · \(skipped) skipped")
    }

    static func detail(_ row: CSVImportRow, line: Int, categories: [CategoryRecord]) -> String {
        let date = row.occurredAt.formatted(date: .abbreviated, time: .omitted)
        let amount = LedgerFormat.signedAmount(row.amount, type: row.type)
        let category = categories.first { $0.id == row.categoryID }?.name ?? String(localized: "Uncategorized")
        return "\(date) · \(amount) · \(category) · " + String(localized: "line \(line)")
    }

    static func reason(_ reason: CSVSkipReason) -> String {
        switch reason {
        case .missingDate: return String(localized: "No date.")
        case .unreadableDate(let text): return String(localized: "“\(text)” isn't a date in the chosen format.")
        case .missingAmount: return String(localized: "No amount.")
        case .unreadableAmount(let text): return String(localized: "“\(text)” isn't an amount.")
        case .zeroAmount: return String(localized: "The amount is zero.")
        }
    }
}
