import HouseholdHubCore
import SwiftData
import SwiftUI

/// Floating Quick Add button shown over every tab (spec §24.3).
struct QuickAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .clipShape(Circle())
        .accessibilityLabel("Quick Add")
        .accessibilityHint("Record an expense or income")
        .accessibilityIdentifier("quickadd.button")
    }
}

/// Quick Add sheet (spec §24.3): one autofocused field parsed by the §25 grammar, progressive details, and a
/// Save button that stays disabled until the draft is valid.
struct QuickAddView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var text = ""
    @State private var type = TransactionType.expense
    @State private var amountText = ""
    @State private var categoryID: UUID?
    @State private var occurredAt = Date.now
    @State private var notes = ""
    @State private var showDetails = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Which fields the quick text currently supplies; those follow the text, manual edits are kept.
    @State private var typeFromText = false
    @State private var amountFromText = false
    @State private var categoryFromText = false
    @FocusState private var quickFieldFocused: Bool

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }
    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: currencyCode) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("47.50 coffee", text: $text)
                        .focused($quickFieldFocused)
                        .submitLabel(.done)
                        .accessibilityLabel("Quick entry")
                        .accessibilityHint("Type an amount and a description, for example 47.50 coffee")
                        .accessibilityIdentifier("quickadd.text")
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("quickadd.type")
                }
                if showDetails {
                    detailsSection
                } else {
                    Button("Add details") { showDetails = true }
                        .accessibilityIdentifier("quickadd.details")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(amount == nil || isSaving)
                        .accessibilityIdentifier("quickadd.save")
                }
            }
            .onChange(of: text) { applyParse() }
            .onAppear { quickFieldFocused = true }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("quickadd.amount")
            Picker("Category", selection: $categoryID) {
                Text("None").tag(UUID?.none)
                ForEach(usableCategories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
            TextField("Notes", text: $notes)
                .accessibilityIdentifier("quickadd.notes")
        }
    }

    private var usableCategories: [CategoryRecord] {
        categories.filter { !$0.isArchived && $0.kind.allows(type) }
    }

    /// Mirrors the parse into the structured fields; the fields stay editable afterwards (§25.4).
    private func applyParse() {
        guard let currency = try? Currency(code: currencyCode) else { return }
        let options = categories.filter { !$0.isArchived }.map {
            QuickAddCategoryOption(id: $0.id, name: $0.name, kind: $0.kind)
        }
        let parser = QuickAddParser(
            currency: currency, categories: options, calendar: HouseholdCalendar(timeZone: .current))
        let parsed = parser.parse(text, now: .now)
        if parsed.type == .income {
            type = .income
            typeFromText = true
        } else if typeFromText {
            type = .expense
            typeFromText = false
        }
        if let parsedAmount = parsed.amount {
            amountText = LedgerFormat.editableAmount(parsedAmount)
            amountFromText = true
            showDetails = true
        } else if amountFromText {
            amountText = ""
            amountFromText = false
        }
        if let parsedCategory = parsed.categoryID {
            categoryID = parsedCategory
            categoryFromText = true
        } else if categoryFromText {
            categoryID = nil
            categoryFromText = false
        }
        occurredAt = parsed.occurredAt
        notes = parsed.description
    }

    private func save() async {
        guard let services, let amount, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        if let categoryID, let category = categories.first(where: { $0.id == categoryID }),
            !category.kind.allows(type)
        {
            errorMessage = String(localized: "\(category.name) can't be used for this type. Choose another category.")
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let draft = TransactionDraft(
            amount: amount, type: type, occurredAt: occurredAt, categoryID: categoryID,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        do {
            try await services.transactions.create(draft, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "This couldn't be saved. Check the amount and category.")
        }
    }
}
