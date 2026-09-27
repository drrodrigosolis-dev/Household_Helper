import HouseholdHubCore
import SwiftData
import SwiftUI

/// Transaction detail and edit (spec §7.2). Saves through `TransactionService.update`; provenance is kept. An expense
/// offers Refund… (Sprint 20); a refund edits its amount, date, status and note through `updateRefund`.
struct TransactionEditorView: View {
    let record: TransactionRecord

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    /// Tasks that link this transaction (spec §2.1 links); shown read-only, the link is edited on the task.
    @Query private var linkedTasks: [TaskItem]
    /// This expense's refunds, or for a refund, its purchase (Sprint 20).
    @Query private var refunds: [TransactionRecord]
    @Query private var refundedPurchase: [TransactionRecord]
    @State private var refundSummary: RefundSummary?
    /// The wishlist item this purchase bought, if any: once fully refunded, the owner decides keep or remove.
    @Query private var boughtItems: [WishlistItem]
    @State private var isRefunding = false

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
        _refunds = Query(
            filter: #Predicate<TransactionRecord> { $0.refundOfTransactionID == id }, sort: \.occurredAt)
        _boughtItems = Query(filter: #Predicate<WishlistItem> { $0.purchasedTransactionID == id })
        if let purchaseID = record.refundOfTransactionID {
            _refundedPurchase = Query(filter: #Predicate<TransactionRecord> { $0.id == purchaseID })
        } else {
            _refundedPurchase = Query(filter: #Predicate<TransactionRecord> { _ in false })
        }
    }

    private var isRefund: Bool { record.type == .refund }

    /// Refund… is offered on a live expense (Sprint 20 decision 4).
    private var canBeRefunded: Bool { record.type == .expense && record.status != .cancelled }

    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: record.currencyCode) }

    /// Active categories valid for the chosen type, plus the current one even if it was archived since.
    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(type) }
    }

    private var isPurchase: Bool { record.source == .wishlistPurchase || record.wishlistItemID != nil }

    /// Cancelling a purchase, or one with refunds, is refused by the service; deleting a wishlist purchase reverts
    /// its item instead.
    private var selectableStatuses: [TransactionStatus] {
        isPurchase || !refunds.isEmpty ? [.posted, .pending] : TransactionStatus.allCases
    }

    var body: some View {
        Form {
            Section {
                // A wishlist purchase stays one expense (spec §8.1), and a refund stays a refund of its purchase, so
                // neither offers a type change; nor does an expense that has refunds.
                if isRefund {
                    LabeledContent("Type", value: String(localized: "Refund"))
                } else if isPurchase {
                    LabeledContent("Type", value: String(localized: "Wishlist purchase"))
                } else if !refunds.isEmpty {
                    LabeledContent("Type", value: String(localized: "Expense"))
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
            if isRefund {
                refundDetails
            } else {
                classification
            }
            if canBeRefunded {
                refundSection
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
        .navigationTitle(isRefund ? "Refund" : "Transaction")
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(amount == nil || isSaving)
                    .accessibilityIdentifier("editor.save")
            }
        }
        .task(id: refunds.map(\.updatedAt)) { await loadRefundSummary() }
        .sheet(isPresented: $isRefunding) {
            if let refundSummary {
                NavigationStack { RefundView(purchase: record, summary: refundSummary) }
            }
        }
    }

    /// Account, category, merchant and note of an ordinary transaction.
    private var classification: some View {
        Section {
            // Active accounts, plus the record's own even if it was archived since (Sprint 10).
            let pickable = accounts.filter { !$0.isArchived || $0.id == accountID }
            if pickable.count > 1 {
                Picker("Account", selection: $accountID) {
                    ForEach(pickable) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                // Refunds stay in the purchase's account (Sprint 20 decision 6).
                .disabled(!refunds.isEmpty)
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
    }

    /// A refund's link and classification come from its purchase and are shown, not edited.
    private var refundDetails: some View {
        Section {
            if let purchase = refundedPurchase.first {
                LabeledContent("Refund for") {
                    Text(Self.purchaseTitle(purchase, category: categories.first { $0.id == purchase.categoryID }))
                }
                LabeledContent("Paid", value: purchase.amount.formatted())
            }
            if let category = categories.first(where: { $0.id == record.categoryID }) {
                LabeledContent("Category", value: category.name)
            }
            if accounts.count > 1, let account = accounts.first(where: { $0.id == record.accountID }) {
                LabeledContent("Account", value: account.name)
            }
            FocusingRow("Notes") {
                TextField("Optional", text: $notes, axis: .vertical)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// What has come back for this expense, and Refund… while something is left (Sprint 20).
    private var refundSection: some View {
        Section {
            if let refundSummary, refundSummary.hasRefunds {
                LabeledContent("Refunded") {
                    Text("\(refundSummary.refunded.formatted()) of \(refundSummary.paid.formatted())")
                }
                .accessibilityIdentifier("editor.refundSummary")
                ForEach(refunds) { refund in
                    LabeledContent {
                        Text(LedgerFormat.signedAmount(refund.amount, type: .refund))
                            .strikethrough(refund.status == .cancelled)
                    } label: {
                        Text(refund.occurredAt.formatted(date: .abbreviated, time: .omitted))
                        if refund.status != .posted {
                            Text(LedgerFormat.statusText(refund.status))
                        }
                    }
                }
            }
            if refundSummary?.isFullyRefunded == true {
                Label("Fully refunded", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                // Asked when the refund was made; offered here too in case that answer never arrived (the dialog
                // was left, or the refund was completed by editing).
                if let item = boughtItems.first, item.status == .purchased {
                    Text("Keep \(item.name) on your wishlist?")
                    Button("Keep on wishlist") { Task { await resolve(item.id, .keepOnWishlist) } }
                        .accessibilityIdentifier("editor.keepOnWishlist")
                    Button("Remove from wishlist", role: .destructive) {
                        Task { await resolve(item.id, .removeFromWishlist) }
                    }
                    .accessibilityIdentifier("editor.removeFromWishlist")
                }
            } else {
                Button("Refund…", systemImage: "arrow.uturn.backward") { isRefunding = true }
                    .disabled(refundSummary == nil)
                    .accessibilityIdentifier("editor.refund")
            }
        } header: {
            Text("Refunds")
        } footer: {
            if !refunds.isEmpty {
                Text("A purchase with refunds keeps its type and account. Delete its refunds to change those.")
            }
        }
    }

    static func purchaseTitle(_ purchase: TransactionRecord, category: CategoryRecord?) -> String {
        let name = purchase.merchantNameSnapshot ?? purchase.notes ?? category?.name
        let date = purchase.occurredAt.formatted(date: .abbreviated, time: .omitted)
        return name.map { "\($0) · \(date)" } ?? date
    }

    private func resolve(_ item: UUID, _ choice: RefundedItemChoice) async {
        do {
            try await services?.transactions.resolveRefundedWishlistItem(item, choice: choice, now: .now)
        } catch {
            errorMessage = String(localized: "The wishlist item couldn't be updated.")
        }
    }

    private func loadRefundSummary() async {
        guard canBeRefunded, let services else { return }
        refundSummary = try? await services.transactions.refundSummary(for: record.id)
    }

    private func save() async {
        guard let services, let amount, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        if !isRefund, let category = categories.first(where: { $0.id == categoryID }), !category.kind.allows(type) {
            errorMessage = String(localized: "\(category.name) can't be used for this type. Choose another category.")
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TransactionDraft(
            amount: amount, type: type, occurredAt: occurredAt, status: status, categoryID: categoryID,
            merchantName: merchant, notes: trimmedNotes.isEmpty ? nil : trimmedNotes, accountID: accountID)
        do {
            if isRefund {
                try await services.transactions.updateRefund(
                    record.id, amount: amount, occurredAt: occurredAt, status: status,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes, calendar: HouseholdCalendar(timeZone: .current),
                    now: .now)
            } else {
                try await services.transactions.update(record.id, with: draft, now: .now)
            }
            dismiss()
        } catch LedgerError.purchaseHasRefunds {
            errorMessage = String(
                localized: """
                    This purchase has refunds: it keeps its type and account, can't be cancelled, and its amount \
                    can't go below what was refunded.
                    """)
        } catch let error as LedgerError where isRefund {
            errorMessage = RefundView.message(for: error)
        } catch {
            errorMessage = String(localized: "Changes couldn't be saved. Check the amount and category.")
        }
    }
}
