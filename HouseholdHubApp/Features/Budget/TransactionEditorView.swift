import HouseholdHubCore
import SwiftData
import SwiftUI

/// Transaction detail and edit (spec §7.2). Saves through `TransactionService.update`; provenance is kept.
struct TransactionEditorView: View {
    let record: TransactionRecord

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]

    @State private var type: TransactionType
    @State private var amountText: String
    @State private var occurredAt: Date
    @State private var status: TransactionStatus
    @State private var categoryID: UUID?
    @State private var merchant: String
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(record: TransactionRecord) {
        self.record = record
        _type = State(initialValue: record.type)
        _amountText = State(initialValue: LedgerFormat.editableAmount(record.amount))
        _occurredAt = State(initialValue: record.occurredAt)
        _status = State(initialValue: record.status)
        _categoryID = State(initialValue: record.categoryID)
        _merchant = State(initialValue: record.merchantNameSnapshot ?? "")
        _notes = State(initialValue: record.notes ?? "")
    }

    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: record.currencyCode) }

    /// Active categories valid for the chosen type, plus the current one even if it was archived since.
    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(type) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $type) {
                    Text("Expense").tag(TransactionType.expense)
                    Text("Income").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("editor.amount")
                DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                Picker("Status", selection: $status) {
                    ForEach(TransactionStatus.allCases, id: \.self) { status in
                        Text(LedgerFormat.statusLabel(status)).tag(status)
                    }
                }
            }
            Section {
                Picker("Category", selection: $categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(pickableCategories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
                TextField("Merchant", text: $merchant)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            if record.recurringSeriesID != nil {
                Section {
                    Label("Part of a recurring series", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(amount == nil || isSaving)
                    .accessibilityIdentifier("editor.save")
            }
        }
    }

    private func save() async {
        guard let services, let amount, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        if let category = categories.first(where: { $0.id == categoryID }), !category.kind.allows(type) {
            errorMessage = String(localized: "\(category.name) can't be used for this type. Choose another category.")
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TransactionDraft(
            amount: amount, type: type, occurredAt: occurredAt, status: status, categoryID: categoryID,
            merchantName: merchant, notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
        do {
            try await services.transactions.update(record.id, with: draft, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "Changes couldn't be saved. Check the amount and category.")
        }
    }
}
