import HouseholdHubCore
import SwiftData
import SwiftUI

/// Transaction detail and edit (spec §7.2). Saves through `TransactionService.update`; provenance is kept.
struct TransactionEditorView: View {
    let record: TransactionRecord

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    /// Tasks that link this transaction (spec §2.1 links); shown read-only, the link is edited on the task.
    @Query private var linkedTasks: [TaskItem]

    @State private var type: TransactionType
    @State private var amountText: String
    @State private var occurredAt: Date
    @State private var status: TransactionStatus
    @State private var categoryID: UUID?
    @State private var merchant: String
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var accountID: UUID?

    init(record: TransactionRecord) {
        self.record = record
        _type = State(initialValue: record.type)
        _amountText = State(initialValue: LedgerFormat.editableAmount(record.amount))
        _occurredAt = State(initialValue: record.occurredAt)
        _status = State(initialValue: record.status)
        _categoryID = State(initialValue: record.categoryID)
        _merchant = State(initialValue: record.merchantNameSnapshot ?? "")
        _notes = State(initialValue: record.notes ?? "")
        _accountID = State(initialValue: record.accountID)
        let id: UUID? = record.id
        _linkedTasks = Query(filter: #Predicate<TaskItem> { $0.linkedTransactionID == id }, sort: \.createdAt)
    }

    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: record.currencyCode) }

    /// Active categories valid for the chosen type, plus the current one even if it was archived since.
    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(type) }
    }

    private var isPurchase: Bool { record.source == .wishlistPurchase || record.wishlistItemID != nil }

    /// Cancelling a purchase is refused by the service; deleting it reverts the wishlist item instead.
    private var selectableStatuses: [TransactionStatus] {
        isPurchase ? [.posted, .pending] : TransactionStatus.allCases
    }

    var body: some View {
        Form {
            Section {
                // A wishlist purchase stays one expense (spec §8.1), so its type is not offered for change.
                if isPurchase {
                    LabeledContent("Type", value: String(localized: "Wishlist purchase"))
                } else {
                    Picker("Type", selection: $type) {
                        Text("Expense").tag(TransactionType.expense)
                        Text("Income").tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }
                FocusingRow("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("editor.amount")
                }
                DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                Picker("Status", selection: $status) {
                    ForEach(selectableStatuses, id: \.self) { status in
                        Text(LedgerFormat.statusLabel(status)).tag(status)
                    }
                }
            }
            Section {
                // Active accounts, plus the record's own even if it was archived since (Sprint 10).
                let pickable = accounts.filter { !$0.isArchived || $0.id == accountID }
                if pickable.count > 1 {
                    Picker("Account", selection: $accountID) {
                        ForEach(pickable) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                    .accessibilityIdentifier("editor.account")
                }
                Picker("Category", selection: $categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(pickableCategories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
                FocusingRow("Merchant") {
                    TextField("Optional", text: $merchant)
                        .multilineTextAlignment(.trailing)
                }
                FocusingRow("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            }
            if record.recurringSeriesID != nil {
                Section {
                    Label("Part of a recurring series", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
            if !linkedTasks.isEmpty {
                Section("Linked tasks") {
                    ForEach(linkedTasks) { task in
                        Label(task.title, systemImage: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                            .accessibilityIdentifier("editor.linkedTask")
                    }
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
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
            merchantName: merchant, notes: trimmedNotes.isEmpty ? nil : trimmedNotes, accountID: accountID)
        do {
            try await services.transactions.update(record.id, with: draft, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "Changes couldn't be saved. Check the amount and category.")
        }
    }
}
