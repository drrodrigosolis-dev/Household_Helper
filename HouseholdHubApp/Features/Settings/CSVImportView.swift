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
    private let presetStore: CSVImportPresetStore

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
    /// Learned categories by normalized merchant name (Sprint 23, A-006), loaded with the duplicate check.
    @State private var suggestions: [String: UUID] = [:]
    /// Bumped by each duplicate-check load, so the preview follows the latest one.
    @State private var loadGeneration = 0
    @State private var rows: [CSVPreviewRow] = []
    /// The user's own tick or untick per file line; rows without one follow the default (ready, not a duplicate).
    @State private var choices: [Int: Bool] = [:]
    /// The user's own category per file line (nil inside = Uncategorized); rows without one take the file's category,
    /// else the suggestion.
    @State private var categoryChoices: [Int: UUID?] = [:]
    @State private var isConfirming = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Saved bank presets (Sprint 23, F8): a device setting, not app data.
    @State private var presets: [CSVImportPreset]
    @State private var selectedPresetID: UUID?
    @State private var hasAutoAppliedPreset = false
    @State private var isPromptingPresetName = false
    @State private var newPresetName = ""

    private let calendar = HouseholdCalendar(timeZone: .current)

    init(
        source: CSVImportSource, presetStore: CSVImportPresetStore = CSVImportPresetStore(),
        onImported: @escaping (Int) -> Void
    ) {
        self.source = source
        self.presetStore = presetStore
        self.onImported = onImported
        _presets = State(initialValue: presetStore.all())
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

    private var loadKey: LoadKey {
        LoadKey(account: chosenAccountID, dateColumn: columns[.date], descriptionColumn: columns[.description])
    }

    private func isIncluded(_ row: CSVPreviewRow) -> Bool {
        guard row.row != nil else { return false }
        return choices[row.line] ?? !row.isLikelyDuplicate
    }

    /// The saved preset this file's header matches, if any: shown as auto-selected with a note.
    private var autoMatchedPreset: CSVImportPreset? {
        presets.first { $0.matches(header: source.header) }
    }

    /// A file's columns, date format and decimal mark are mapped enough to name and save a preset for it.
    private var canSavePreset: Bool {
        columns[.date] != nil && columns[.amount] != nil && dateFormat != nil && decimalMark != nil
            && chosenAccountID != nil
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
        let ready = !included.isEmpty && chosenAccountID != nil && missingChoice == nil && existing != nil
        Form {
            presetSection
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
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { isConfirming = true }
                    .disabled(!ready || isSaving)
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
        .task(id: loadKey) { await loadExisting() }
        .onChange(of: inputs, initial: true) { recompute() }
        .onAppear { applyAutoMatchedPresetIfNeeded() }
        .alert("Save as preset", isPresented: $isPromptingPresetName) {
            TextField("Name", text: $newPresetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A file with the same column headers will use this mapping automatically next time.")
        }
    }

    private var presetSection: some View {
        Section {
            Picker("Preset", selection: presetBinding) {
                Text("None").tag(UUID?.none)
                ForEach(presets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .accessibilityIdentifier("csv.preset")
            if let autoMatchedPreset, selectedPresetID == autoMatchedPreset.id {
                Text("Matched your preset “\(autoMatchedPreset.name)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save as preset…") {
                newPresetName = ""
                isPromptingPresetName = true
            }
            .disabled(!canSavePreset)
            .accessibilityIdentifier("csv.savePreset")
            NavigationLink("Import presets") {
                CSVImportPresetListView(presetStore: presetStore, presets: $presets)
            }
        } header: {
            Text("Preset")
        }
    }

    private var presetBinding: Binding<UUID?> {
        Binding(
            get: { selectedPresetID },
            set: { newValue in
                selectedPresetID = newValue
                guard let id = newValue, let preset = presets.first(where: { $0.id == id }) else { return }
                apply(preset)
            })
    }

    /// Applies a saved preset's mapping, and its account when that account is still active; otherwise the account
    /// picker's own default stands.
    private func apply(_ preset: CSVImportPreset) {
        columns = preset.columns
        dateFormat = preset.dateFormat
        decimalMark = preset.decimalMark
        spendingIsPositive = preset.spendingIsPositive
        let active = Set(accounts.filter { !$0.isArchived }.map(\.id))
        if let target = preset.targetAccountID(activeAccountIDs: active) {
            accountID = target
        }
    }

    private func applyAutoMatchedPresetIfNeeded() {
        guard !hasAutoAppliedPreset else { return }
        hasAutoAppliedPreset = true
        guard let matched = autoMatchedPreset else { return }
        selectedPresetID = matched.id
        apply(matched)
    }

    private func savePreset() {
        guard let dateFormat, let decimalMark, let accountID = chosenAccountID else { return }
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let preset = CSVImportPreset(
            name: name, columns: columns, dateFormat: dateFormat, decimalMark: decimalMark,
            spendingIsPositive: spendingIsPositive, accountID: accountID, headerSignature: source.header)
        presetStore.save(preset)
        presets = presetStore.all()
        selectedPresetID = preset.id
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
            Text(
                """
                Categories are matched by name, or suggested from the category you last gave the same merchant. You \
                can change any row's category below.
                """
            )
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
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: includedBinding(row)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.description ?? String(localized: "No description"))
                        Text(CSVImportFormat.detail(entry, line: row.line))
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
                Picker("Category", selection: categoryBinding(row)) {
                    Text("Uncategorized").tag(UUID?.none)
                    ForEach(categoryOptions(for: entry.type), id: \.id) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .accessibilityIdentifier("csv.row.category")
                if isShowingSuggestion(row) {
                    Label("Suggested: you filed this merchant here before", systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("csv.row.suggested")
                }
            }
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

    /// Active categories that allow `type`: what a row may be filed under.
    private func categoryOptions(for type: TransactionType) -> [CategoryRecord] {
        categoryRecords.filter { !$0.isArchived && $0.kind.allows(type) }
    }

    /// The category the row is imported under: the user's pick while it still fits the row (a later change of sign
    /// can make it an income), else the file's category, else the suggestion.
    private func category(of row: CSVPreviewRow) -> UUID? {
        guard let entry = row.row else { return nil }
        let proposed = entry.categoryID ?? row.suggestedCategoryID
        guard let choice = categoryChoices[row.line] else { return proposed }
        guard let chosen = choice else { return nil }
        return categoryOptions(for: entry.type).contains { $0.id == chosen } ? chosen : proposed
    }

    private func isShowingSuggestion(_ row: CSVPreviewRow) -> Bool {
        guard let suggested = row.suggestedCategoryID else { return false }
        return category(of: row) == suggested
    }

    private func categoryBinding(_ row: CSVPreviewRow) -> Binding<UUID?> {
        Binding(get: { category(of: row) }, set: { categoryChoices[row.line] = .some($0) })
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
            categories: categories, existing: existing, suggestions: suggestions, calendar: calendar)
    }

    /// Recorded transactions in the chosen account over the file's whole date span (any format that reads it).
    private func loadExisting() async {
        guard let services, let account = chosenAccountID else { return }
        existing = nil
        existingFailed = false
        // Suggestions are only a convenience: without them every uncategorized row stays Uncategorized.
        let descriptions = source.values(of: columns[.description])
        suggestions = (try? await services.transactions.importCategorySuggestions(for: descriptions)) ?? [:]
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
            // Each row goes in under the category the preview shows for it, chosen or accepted by the user.
            let filed = rows.compactMap { row in row.row.map { $0.filed(under: category(of: row)) } }
            let count = try await services.transactions.importTransactions(filed, into: account, now: .now)
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
    /// The suggestions are looked up by the description column's names.
    let descriptionColumn: Int?
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

    /// Date, signed amount and file line; the category has its own picker below.
    static func detail(_ row: CSVImportRow, line: Int) -> String {
        let date = row.occurredAt.formatted(date: .abbreviated, time: .omitted)
        let amount = LedgerFormat.signedAmount(row.amount, type: row.type)
        return "\(date) · \(amount) · " + String(localized: "line \(line)")
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
