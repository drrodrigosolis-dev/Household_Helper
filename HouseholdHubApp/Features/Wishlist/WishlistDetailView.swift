import HouseholdHubCore
import SwiftData
import SwiftUI

/// Item detail (spec §24.2): photo, facts, Mark Purchased (§8.1), edit, archive, and the §8.2 delete choice.
struct WishlistDetailView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [WishlistItem]
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]

    @State private var isEditing = false
    @State private var isPurchasing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(itemID: UUID) {
        _matches = Query(filter: #Predicate<WishlistItem> { $0.id == itemID })
    }

    var body: some View {
        Group {
            if let item = matches.first {
                details(item)
            } else {
                ContentUnavailableView("Item not found", systemImage: "heart.slash")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(_ item: WishlistItem) -> some View {
        List {
            if item.mediaReference != nil {
                Section {
                    WishlistThumbnail(reference: item.mediaReference, size: nil)
                        .frame(maxWidth: 280)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                LabeledContent("Estimated price", value: WishlistFormat.estimateText(item.estimatedPrice))
                if let actual = item.actualPrice {
                    LabeledContent("Paid", value: actual.formatted())
                }
                LabeledContent("Priority", value: WishlistFormat.priorityText(item.priority))
                LabeledContent("Status", value: WishlistFormat.statusText(item.status))
                if let category = categories.first(where: { $0.id == item.categoryID }) {
                    LabeledContent("Category", value: category.name)
                }
                if let target = item.targetDate {
                    LabeledContent("Target date", value: target.formatted(date: .abbreviated, time: .omitted))
                }
                if let notes = item.notes {
                    Text(notes)
                }
            }
            Section {
                if item.status == .wanted || item.status == .pending {
                    Button("Mark Purchased", systemImage: "checkmark.circle") { isPurchasing = true }
                        .accessibilityIdentifier("wishlist.markPurchased")
                }
                if item.status == .purchased {
                    Label("Recorded in Budget as an expense", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                if item.status == .archived {
                    Button("Restore", systemImage: "tray.and.arrow.up") { setArchived(false, item) }
                } else {
                    Button("Archive", systemImage: "archivebox") { setArchived(true, item) }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    .accessibilityIdentifier("wishlist.delete")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .accessibilityIdentifier("wishlist.edit")
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { WishlistEditorView(item: item) }
        }
        .sheet(isPresented: $isPurchasing) {
            NavigationStack { WishlistPurchaseView(item: item) }
        }
        .confirmationDialog(
            "Delete \(item.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            deleteActions(item)
        } message: {
            Text(deleteMessage(item))
        }
    }

    /// Spec §8.2: with a linked purchase, offer archiving next to deleting, and say the expense stays.
    @ViewBuilder
    private func deleteActions(_ item: WishlistItem) -> some View {
        if item.purchasedTransactionID != nil, item.status != .archived {
            Button("Archive item") { setArchived(true, item) }
        }
        Button("Delete item", role: .destructive) { delete(item) }
        Button("Cancel", role: .cancel) {}
    }

    private func deleteMessage(_ item: WishlistItem) -> String {
        if item.purchasedTransactionID != nil {
            return String(localized: "Its purchase stays in Budget and in your balances. Only the wishlist item goes.")
        }
        return String(localized: "The item and its photo will be removed.")
    }

    private func setArchived(_ archived: Bool, _ item: WishlistItem) {
        let id = item.id
        Task {
            do {
                try await services?.transactions.setWishlistItemArchived(archived, item: id, now: .now)
            } catch {
                errorMessage = String(localized: "This item couldn't be updated.")
            }
        }
    }

    private func delete(_ item: WishlistItem) {
        guard let services else { return }
        let id = item.id
        Task {
            do {
                let media = try await services.transactions.deleteWishlistItem(id, now: .now)
                if let media {
                    try? services.images?.delete(media)
                }
                dismiss()
            } catch {
                errorMessage = String(localized: "This item couldn't be deleted.")
            }
        }
    }
}

/// Mark Purchased (spec §8.1): confirm the price actually paid, the date, and the category; one expense is recorded
/// and linked in a single save.
struct WishlistPurchaseView: View {
    let item: WishlistItem

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]

    @State private var priceText: String
    @State private var purchasedAt = Date.now
    @State private var categoryID: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(item: WishlistItem) {
        self.item = item
        let estimate = item.estimatedPrice
        _priceText = State(initialValue: estimate.minorUnits > 0 ? LedgerFormat.editableAmount(estimate) : "")
        _categoryID = State(initialValue: item.categoryID)
    }

    private var price: Money? { LedgerFormat.parseAmount(priceText, currencyCode: item.currencyCode) }

    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(.expense) }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Price paid") {
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("wishlist.purchase.price")
                }
                DatePicker("Date", selection: $purchasedAt, in: ...Date.now, displayedComponents: [.date])
                Picker("Category", selection: $categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(pickableCategories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            } footer: {
                Text("Records one expense in Budget and marks \(item.name) as purchased.")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Mark Purchased")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Record") { Task { await purchase() } }
                    .disabled(price == nil || isSaving)
                    .accessibilityIdentifier("wishlist.purchase.confirm")
            }
        }
    }

    private func purchase() async {
        guard let services, let price, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.transactions.purchaseWishlistItem(
                item.id, actualPrice: price, occurredAt: purchasedAt, categoryID: categoryID, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "The purchase couldn't be recorded. Nothing was changed.")
        }
    }
}
