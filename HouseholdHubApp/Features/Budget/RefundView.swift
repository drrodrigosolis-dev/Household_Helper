import HouseholdHubCore
import SwiftUI

/// Refund… from a purchase's editor (Sprint 20): money coming back for it, on the day it comes back. The purchase
/// stays as it was; the refund is its own record, linked to it.
struct RefundView: View {
    let purchase: TransactionRecord
    let summary: RefundSummary

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var occurredAt = Date.now
    @State private var status = TransactionStatus.posted
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Set when this refund completed a wishlist purchase's refund: the owner chooses what happens to the item.
    @State private var itemToResolve: UUID?
    /// Whether the keep-or-remove question is showing. Kept apart from `itemToResolve`: the alert clears its binding
    /// as it closes, before the chosen button's task runs, and clearing the item with it made both choices do nothing
    /// (run 36362839424: the refund sheet stayed open and the item unresolved).
    @State private var isAsking = false

    init(purchase: TransactionRecord, summary: RefundSummary) {
        self.purchase = purchase
        self.summary = summary
        _amountText = State(initialValue: LedgerFormat.editableAmount(summary.remaining))
        _status = State(initialValue: purchase.status == .pending ? .pending : .posted)
    }

    private var amount: Money? { LedgerFormat.parseAmount(amountText, currencyCode: purchase.currencyCode) }

    /// Not before the purchase's day (the service checks the same with the household calendar).
    private var earliest: Date { HouseholdCalendar(timeZone: .current).startOfDay(for: purchase.occurredAt) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Paid", value: summary.paid.formatted())
                if summary.hasRefunds {
                    LabeledContent("Already refunded", value: summary.refunded.formatted())
                }
                LabeledContent("Left to refund", value: summary.remaining.formatted())
                    .accessibilityIdentifier("refund.remaining")
            }
            Section {
                FocusingRow("Amount") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("refund.amount")
                }
                DatePicker("Date", selection: $occurredAt, in: earliest..., displayedComponents: [.date])
                // While the purchase is pending, so is its refund: posting it would add money that hasn't left yet.
                if purchase.status == .pending {
                    LabeledContent("Status") { Text(LedgerFormat.statusLabel(.pending)) }
                } else {
                    Picker("Status", selection: $status) {
                        Text(LedgerFormat.statusLabel(.posted)).tag(TransactionStatus.posted)
                        Text(LedgerFormat.statusLabel(.pending)).tag(TransactionStatus.pending)
                    }
                }
                FocusingRow("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("The purchase stays in your history. The refund adds the money back on its own date.")
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle("Refund")
        .themedScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Refund") { Task { await save() } }
                    .disabled(amount == nil || isSaving)
                    .accessibilityIdentifier("refund.save")
            }
        }
        .alert("Keep it on your wishlist?", isPresented: $isAsking) {
            Button("Keep on wishlist") { choose(.keepOnWishlist) }
                .accessibilityIdentifier("refund.keep")
            Button("Remove from wishlist", role: .destructive) { choose(.removeFromWishlist) }
                .accessibilityIdentifier("refund.remove")
        } message: {
            Text("This purchase is fully refunded. Keep the item on your wishlist to buy it again, or remove it.")
        }
        .interactiveDismissDisabled(itemToResolve != nil)
    }

    /// Reads the item when the button is tapped, not when the task runs.
    private func choose(_ choice: RefundedItemChoice) {
        guard let item = itemToResolve else { return }
        Task { await resolve(choice, item: item) }
    }

    private func save() async {
        guard let services, let amount, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let result = try await services.transactions.refundTransaction(
                purchase.id, amount: amount, occurredAt: occurredAt, status: status, notes: notes,
                calendar: HouseholdCalendar(timeZone: .current), now: .now)
            if let item = result.wishlistItemToResolve {
                itemToResolve = item
                isAsking = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func resolve(_ choice: RefundedItemChoice, item: UUID) async {
        guard let services else { return }
        do {
            try await services.transactions.resolveRefundedWishlistItem(item, choice: choice, now: .now)
            itemToResolve = nil
            dismiss()
        } catch {
            itemToResolve = nil
            errorMessage = String(localized: "The refund was recorded, but the wishlist item couldn't be updated.")
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? LedgerError {
        case .refundExceedsRemaining(let remaining):
            return String(localized: "That's more than what's left to refund (\(remaining.formatted())).")
        case .refundBeforePurchase:
            return String(localized: "A refund can't be dated before the purchase.")
        case .refundOfPendingPurchase:
            return String(localized: "The purchase is still pending, so its refund stays pending until it posts.")
        case .notRefundable:
            return String(localized: "Only a posted or pending expense can be refunded.")
        default:
            return String(localized: "The refund couldn't be recorded. Nothing was changed.")
        }
    }
}
