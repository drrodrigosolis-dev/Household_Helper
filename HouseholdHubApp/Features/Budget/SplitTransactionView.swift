import HouseholdHubCore
import SwiftData
import SwiftUI

/// Split… from an expense's or income's editor (Sprint 23, F4): one payment divided into 2 to 10 parts, each with its
/// own amount, category and note. The parts share the date, status, account and merchant, and must add up to the
/// total exactly: "Left to assign" reaches zero before Save. Part 1 starts at the whole total and keeps whatever the
/// other parts leave, so typing part 2 is enough; once the user types in part 1 it keeps what they typed.
struct SplitTransactionView: View {
    let record: TransactionRecord
    /// Called once the split is saved, so the editor (now showing part one) can close after this sheet.
    let onSplit: () -> Void

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @State private var rows: [Row]
    @State private var errorMessage: String?
    @State private var isSaving = false

    struct Row: Identifiable {
        let id = UUID()
        var amountText = ""
        var categoryID: UUID?
        var notes = ""
        /// The amount is what the other parts leave, until the user types in it.
        var followsRemainder = false
    }

    init(record: TransactionRecord, onSplit: @escaping () -> Void) {
        self.record = record
        self.onSplit = onSplit
        let first = Row(
            amountText: LedgerFormat.editableAmount(record.amount), categoryID: record.categoryID,
            followsRemainder: true)
        _rows = State(initialValue: [first, Row(categoryID: record.categoryID)])
    }

    /// Each row's amount, nil where it doesn't parse as a positive amount.
    private var amounts: [Money?] {
        rows.map { LedgerFormat.parseAmount($0.amountText, currencyCode: record.currencyCode) }
    }

    /// The total less every amount entered so far; nil only if the sum can't be computed.
    private var remaining: Money? {
        try? SplitPart.remaining(of: record.amount, after: amounts.compactMap { $0 })
    }

    /// The parts to save: every amount entered and adding up exactly, 2 to 10 of them.
    private var parts: [SplitPart]? {
        guard TransactionService.splitPartCount.contains(rows.count), remaining?.isZero == true else { return nil }
        var result: [SplitPart] = []
        for (row, amount) in zip(rows, amounts) {
            guard let amount else { return nil }
            result.append(SplitPart(amount: amount, categoryID: row.categoryID, notes: row.notes))
        }
        return result
    }

    /// Active categories valid for the payment's type, plus its own even if archived since.
    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == record.categoryID || !$0.isArchived) && $0.kind.allows(record.type) }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Total", value: record.amount.formatted())
                LabeledContent("Left to assign") {
                    Text(remaining?.formatted() ?? "")
                        .foregroundStyle(remaining?.isZero == true ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("split.remaining")
            } footer: {
                Text("Every part keeps this payment's date, status, account and merchant.")
            }
            ForEach($rows) { $row in
                Section {
                    FocusingRow("Amount") {
                        TextField("0.00", text: typedAmount($row))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("split.row.amount")
                    }
                    Picker("Category", selection: $row.categoryID) {
                        Text("None").tag(UUID?.none)
                        ForEach(pickableCategories) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                    FocusingRow("Notes") {
                        TextField("Optional", text: $row.notes, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                    }
                    if rows.count > TransactionService.splitPartCount.lowerBound {
                        Button("Remove part", systemImage: "minus.circle", role: .destructive) { remove(row.id) }
                            .accessibilityIdentifier("split.row.remove")
                    }
                } header: {
                    Text("Part \(position(of: row.id))")
                }
            }
            Section {
                Button("Add part", systemImage: "plus.circle") { addRow() }
                    .disabled(rows.count >= TransactionService.splitPartCount.upperBound)
                    .accessibilityIdentifier("split.add")
            } footer: {
                Text("Up to \(TransactionService.splitPartCount.upperBound) parts.")
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle("Split")
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: rows.map(\.amountText)) { rebalance() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(parts == nil || isSaving)
                    .accessibilityIdentifier("split.save")
            }
        }
    }

    private func position(of id: UUID) -> Int {
        (rows.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// The amount field's text; typing in it stops the part following what the others leave.
    private func typedAmount(_ row: Binding<Row>) -> Binding<String> {
        Binding(
            get: { row.wrappedValue.amountText },
            set: { text in
                guard text != row.wrappedValue.amountText else { return }
                row.wrappedValue.amountText = text
                row.wrappedValue.followsRemainder = false
            })
    }

    /// Sets the following part (part 1 until typed in) to what the other parts leave, empty when they take it all.
    private func rebalance() {
        guard let index = rows.firstIndex(where: \.followsRemainder) else { return }
        let parsed = amounts
        let others = parsed.indices.filter { $0 != index }.compactMap { parsed[$0] }
        let text = SplitPart.balancingAmount(of: record.amount, after: others).map(LedgerFormat.editableAmount) ?? ""
        if rows[index].amountText != text {
            rows[index].amountText = text
        }
    }

    /// A new part starts with whatever is left to assign, when something is.
    private func addRow() {
        guard rows.count < TransactionService.splitPartCount.upperBound else { return }
        var row = Row(categoryID: record.categoryID)
        if let remaining, remaining.minorUnits > 0 {
            row.amountText = LedgerFormat.editableAmount(remaining)
        }
        rows.append(row)
    }

    private func remove(_ id: UUID) {
        guard rows.count > TransactionService.splitPartCount.lowerBound else { return }
        rows.removeAll { $0.id == id }
    }

    private func save() async {
        guard let services, let parts, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.transactions.splitTransaction(record.id, into: parts, now: .now)
            onSplit()
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? LedgerError {
        case .splitDoesNotAddUp:
            return String(localized: "The parts must add up to the total.")
        case .alreadySplit:
            return String(localized: "This transaction is already split.")
        case .purchaseHasRefunds:
            return String(localized: "A purchase with refunds can't be split.")
        case .notSplittable:
            return String(
                localized: "Only a posted or pending expense or income can be split, not a recurring or wishlist one.")
        case .archivedCategory, .unknownCategory, .categoryKindMismatch:
            return String(localized: "Choose another category for each part.")
        default:
            return String(localized: "The split couldn't be saved. Nothing was changed.")
        }
    }
}
