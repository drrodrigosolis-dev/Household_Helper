import HouseholdHubCore
import SwiftData
import SwiftUI

/// A transfer between two of the household's accounts (Sprint 10 decisions 5 and 8): new from Budget › New transfer,
/// or an existing one opened from the list. It is neither income nor spending, so it has no category or merchant,
/// and it changes no household total.
struct TransferEditorView: View {
    /// The transfer being edited; nil for a new one.
    let record: TransactionRecord?

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amountText: String
    @State private var occurredAt: Date
    @State private var status: TransactionStatus
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(record: TransactionRecord? = nil) {
        self.record = record
        _fromID = State(initialValue: record?.accountID)
        _toID = State(initialValue: record?.transferAccountID)
        _amountText = State(initialValue: record.map { LedgerFormat.editableAmount($0.amount) } ?? "")
        _occurredAt = State(initialValue: record?.occurredAt ?? .now)
        _status = State(initialValue: record?.status ?? .posted)
        _notes = State(initialValue: record?.notes ?? "")
    }

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }
    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: currencyCode) }

    /// Active accounts, plus the ones this transfer already uses even if archived since.
    private var pickable: [Account] {
        accounts.filter { !$0.isArchived || $0.id == record?.accountID || $0.id == record?.transferAccountID }
    }

    private var canSave: Bool {
        amount != nil && fromID != nil && toID != nil && fromID != toID && !isSaving
    }

    var body: some View {
        Form {
            Section {
                Picker("From", selection: $fromID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(pickable) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .accessibilityIdentifier("transfer.from")
                Picker("To", selection: $toID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(pickable) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .accessibilityIdentifier("transfer.to")
                FocusingRow("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("transfer.amount")
                }
            } footer: {
                if fromID != nil, fromID == toID {
                    Text("Choose two different accounts.")
                } else {
                    Text(
                        """
                        Moves money between your accounts. It isn't income or spending, and the household total \
                        stays the same.
                        """
                    )
                }
            }
            Section {
                DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                Picker("Status", selection: $status) {
                    Text(LedgerFormat.statusLabel(.posted)).tag(TransactionStatus.posted)
                    Text(LedgerFormat.statusLabel(.pending)).tag(TransactionStatus.pending)
                    if record != nil {
                        Text(LedgerFormat.statusLabel(.cancelled)).tag(TransactionStatus.cancelled)
                    }
                }
                FocusingRow("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle(record == nil ? Text("New Transfer") : Text("Transfer"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if record == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("transfer.save")
            }
        }
        .onAppear {
            // A new transfer starts from the default account.
            if record == nil, fromID == nil {
                fromID = settings.first?.defaultAccountID
            }
        }
    }

    private func save() async {
        guard let services, let amount, let fromID, let toID, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TransactionDraft(
            amount: amount, type: .transfer, occurredAt: occurredAt, status: status,
            notes: trimmed.isEmpty ? nil : trimmed, accountID: fromID, transferAccountID: toID)
        do {
            if let record {
                try await services.transactions.update(record.id, with: draft, now: .now)
            } else {
                try await services.transactions.create(draft, now: .now)
            }
            await WidgetSync.refresh(services)
            dismiss()
        } catch {
            errorMessage = String(localized: "The transfer couldn't be saved. Check the amount and accounts.")
        }
    }
}
