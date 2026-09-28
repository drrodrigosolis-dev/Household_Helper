import HouseholdHubCore
import SwiftData
import SwiftUI

/// Transaction detail and edit (spec §7.2). Saves through `TransactionService.update`; provenance is kept. An expense
/// offers Refund… (Sprint 20); a refund edits its amount, date, status and note through `updateRefund`. Sprint 23
/// (F4): Duplicate records the same payment again today; Split… divides it into parts, and a part offers Unsplit.
struct TransactionEditorView: View {
    let record: TransactionRecord

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    /// The transaction list's banner, which reports a merge that failed after the editor closed (absent when the
    /// editor was opened from elsewhere).
    @Environment(UndoCenter.self) private var undoCenter: UndoCenter?
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
    /// Every part of this record's split, itself included; empty when it is not split (Sprint 23).
    @Query private var splitParts: [TransactionRecord]
    @State private var isSplitting = false
    /// Set by the split sheet once it saved: the editor then closes, as this record is now part one.
    @State private var didSplit = false
    @State private var isConfirmingUnsplit = false

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
        if let group = record.splitGroupID {
            let target: UUID? = group
            _splitParts = Query(filter: #Predicate<TransactionRecord> { $0.splitGroupID == target })
        } else {
            _splitParts = Query(filter: #Predicate<TransactionRecord> { _ in false })
        }
    }

    private var isRefund: Bool { record.type == .refund }

    /// Refund… is offered on a live expense (Sprint 20 decision 4).
    private var canBeRefunded: Bool { record.type == .expense && record.status != .cancelled }

    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: record.currencyCode) }

    /// Sprint 23 (A-015): Save waits until an editable field differs from the stored record.
    private var hasChanges: Bool {
        let edits = TransactionEdits(
            type: type, amount: amount, occurredAt: occurredAt, status: status, categoryID: categoryID,
            merchant: merchant, notes: notes, accountID: accountID)
        return edits != TransactionEdits(record: record)
    }

    /// Active categories valid for the chosen type, plus the current one even if it was archived since.
    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(type) }
    }

    private var isPurchase: Bool { record.source == .wishlistPurchase || record.wishlistItemID != nil }

    private var isSplitPart: Bool { record.splitGroupID != nil }

    /// Split… is offered on a live expense or income entered by hand or imported, not yet split and without refunds;
    /// the service refuses the rest (Sprint 23).
    private var canBeSplit: Bool {
        (record.type == .expense || record.type == .income) && record.status != .cancelled && !isSplitPart
            && !isPurchase && record.recurringSeriesID == nil && record.source != .recurring && refunds.isEmpty
    }

    /// Duplicate repeats anything but a refund (made from its purchase) or a cancelled record.
    private var canBeDuplicated: Bool { !isRefund && record.status != .cancelled }

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
                } else if isSplitPart {
                    // The parts of a split share their type (Sprint 23); unsplit to change it.
                    LabeledContent("Type") { Text(LedgerFormat.typeLabel(record.type)) }
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
            if !isRefund {
                splitSection
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
                    .disabled(amount == nil || isSaving || !hasChanges)
                    .accessibilityIdentifier("editor.save")
            }
        }
        .task(id: refunds.map(\.updatedAt)) { await loadRefundSummary() }
        .sheet(isPresented: $isRefunding) {
            if let refundSummary {
                NavigationStack { RefundView(purchase: record, summary: refundSummary) }
            }
        }
        .sheet(isPresented: $isSplitting, onDismiss: closeAfterSplit) {
            NavigationStack {
                SplitTransactionView(record: record) { didSplit = true }
            }
        }
        .confirmationDialog(
            "Merge the parts back into one transaction?", isPresented: $isConfirmingUnsplit,
            titleVisibility: .visible
        ) {
            Button("Unsplit", role: .destructive) { Task { await unsplit() } }
                .accessibilityIdentifier("editor.unsplit.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The first part takes the total and keeps its category and note; the other parts are removed.")
        }
    }

    /// Duplicate, Split… and, on a part of a split, what it belongs to and Unsplit (Sprint 23).
    @ViewBuilder
    private var splitSection: some View {
        Section {
            if isSplitPart {
                Label("Part of a split (\(max(splitParts.count, 1)) parts)", systemImage: "square.split.2x1")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.splitInfo")
                Button("Unsplit", systemImage: "arrow.triangle.merge") { isConfirmingUnsplit = true }
                    .disabled(hasChanges || isSaving)
                    .accessibilityIdentifier("editor.unsplit")
            } else if canBeSplit {
                Button("Split…", systemImage: "square.split.2x1") { isSplitting = true }
                    .disabled(hasChanges || isSaving)
                    .accessibilityIdentifier("editor.split")
            }
            if canBeDuplicated {
                Button("Duplicate", systemImage: "plus.square.on.square") { Task { await duplicate() } }
                    .disabled(hasChanges || isSaving)
                    .accessibilityIdentifier("editor.duplicate")
            }
        } footer: {
            if isSplitPart {
                Text("The parts share their date, status, account and merchant: changing them here changes every part.")
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

    private func closeAfterSplit() {
        if didSplit {
            dismiss()
        }
    }

    /// A new entry dated today; the editor closes and the list shows it at the top.
    private func duplicate() async {
        guard let services, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.transactions.duplicateTransaction(
                record.id, now: .now, calendar: HouseholdCalendar(timeZone: .current))
            dismiss()
        } catch LedgerError.archivedAccount {
            errorMessage = String(localized: "Its account is archived. Choose another account to record it again.")
        } catch {
            errorMessage = String(localized: "The transaction couldn't be duplicated.")
        }
    }

    /// Checked first so a refusal shows here; then the editor closes before the merge, as merging removes every part
    /// but the first, and this one may be among them. A merge that still fails (the data changed in between) changes
    /// nothing, and says so in the transaction list's banner, which outlives this editor (Sprint 23 review S4).
    private func unsplit() async {
        guard let services, !isSaving else { return }
        do {
            try await services.transactions.checkUnsplit(record.id)
        } catch LedgerError.purchaseHasRefunds {
            errorMessage = String(
                localized: "A part has refunds, so the parts can't be merged. Delete its refunds first.")
            return
        } catch {
            errorMessage = String(localized: "The parts couldn't be merged.")
            return
        }
        let id = record.id
        let banner = undoCenter
        dismiss()
        do {
            try await services.transactions.unsplitTransaction(id, now: .now)
        } catch {
            banner?.notify(String(localized: "The parts couldn't be merged. Nothing was changed."))
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

/// The transaction editor's editable fields, compared with the stored record so Save waits for a change (Sprint 23,
/// A-015). Merchant and notes compare as the service stores them: trimmed, with empty meaning none.
struct TransactionEdits: Equatable {
    var type: TransactionType
    /// Nil while the typed amount doesn't parse; that already disables Save.
    var amount: Money?
    var occurredAt: Date
    var status: TransactionStatus
    var categoryID: UUID?
    var merchant: String
    var notes: String
    var accountID: UUID?

    init(
        type: TransactionType, amount: Money?, occurredAt: Date, status: TransactionStatus, categoryID: UUID?,
        merchant: String, notes: String, accountID: UUID?
    ) {
        self.type = type
        self.amount = amount
        self.occurredAt = occurredAt
        self.status = status
        self.categoryID = categoryID
        self.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountID = accountID
    }

    init(record: TransactionRecord) {
        self.init(
            type: record.type, amount: record.amount, occurredAt: record.occurredAt, status: record.status,
            categoryID: record.categoryID, merchant: record.merchantNameSnapshot ?? "", notes: record.notes ?? "",
            accountID: record.accountID)
    }
}
