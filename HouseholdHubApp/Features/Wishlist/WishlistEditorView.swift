import HouseholdHubCore
import PhotosUI
import SwiftData
import SwiftUI

/// Create or edit a wishlist item (spec §7.7). Purchased and archived items keep their status; only details change.
struct WishlistEditorView: View {
    let item: WishlistItem?

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var name: String
    @State private var estimateText: String
    @State private var priority: Priority
    @State private var status: WishlistStatus
    @State private var categoryID: UUID?
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var notes: String
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var removePhoto = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var createdID: UUID?

    init(item: WishlistItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        var estimate = ""
        if let price = item?.estimatedPrice, price.minorUnits > 0 {
            estimate = LedgerFormat.editableAmount(price)
        }
        _estimateText = State(initialValue: estimate)
        _priority = State(initialValue: item?.priority ?? .medium)
        _status = State(initialValue: item?.status ?? .wanted)
        _categoryID = State(initialValue: item?.categoryID)
        _hasTargetDate = State(initialValue: item?.targetDate != nil)
        _targetDate = State(initialValue: item?.targetDate ?? .now)
        _notes = State(initialValue: item?.notes ?? "")
    }

    private var currencyCode: String { item?.currencyCode ?? settings.first?.currencyCode ?? "CAD" }

    /// Empty means "price unknown" (zero); anything else must parse as a positive amount.
    private var estimate: Money? {
        if estimateText.trimmingCharacters(in: .whitespaces).isEmpty {
            return Money(minorUnits: 0, currencyCode: currencyCode)
        }
        return LedgerFormat.parseAmount(estimateText, currencyCode: currencyCode)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && estimate != nil && !isSaving
    }

    private var statusIsEditable: Bool { item == nil || item?.status == .wanted || item?.status == .pending }

    private var pickableCategories: [CategoryRecord] {
        categories.filter { ($0.id == categoryID || !$0.isArchived) && $0.kind.allows(.expense) }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Required", text: $name)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("wishlist.editor.name")
                }
                LabeledContent("Estimated price") {
                    TextField("Optional", text: $estimateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("wishlist.editor.estimate")
                }
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases.reversed(), id: \.self) { value in
                        Text(WishlistFormat.priorityText(value)).tag(value)
                    }
                }
                if statusIsEditable {
                    Picker("Status", selection: $status) {
                        Text(WishlistFormat.statusText(.wanted)).tag(WishlistStatus.wanted)
                        Text(WishlistFormat.statusText(.pending)).tag(WishlistStatus.pending)
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
                Toggle("Target date", isOn: $hasTargetDate)
                if hasTargetDate {
                    DatePicker("Date", selection: $targetDate, displayedComponents: .date)
                }
                LabeledContent("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            }
            photoSection
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle(item == nil ? Text("New Item") : Text("Edit Item"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("wishlist.editor.save")
            }
        }
        .onChange(of: photoItem) { Task { await loadPhoto() } }
    }

    private var photoSection: some View {
        Section("Photo") {
            // Resolved here, on the main actor: PhotosPicker's label closure is Sendable, so it captures only a Bool.
            let replacing = hasPhoto
            PhotosPicker(selection: $photoItem, matching: .images) {
                if replacing {
                    Label("Replace photo", systemImage: "photo")
                } else {
                    Label("Add photo", systemImage: "photo")
                }
            }
            if hasPhoto {
                Button("Remove photo", role: .destructive) {
                    photoItem = nil
                    photoData = nil
                    removePhoto = true
                }
            }
        }
    }

    private var hasPhoto: Bool { photoData != nil || (item?.mediaReference != nil && !removePhoto) }

    private func loadPhoto() async {
        guard let photoItem else { return }
        photoData = try? await photoItem.loadTransferable(type: Data.self)
        removePhoto = false
    }

    /// Order keeps the store and the files consistent: the new file is written first (nothing is saved if that
    /// fails), the reference is stored next, and the replaced file is removed last. A failure leaves at worst an
    /// unreferenced file, never a reference to a missing one.
    private func save() async {
        guard let services, let estimate, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        var newReference: String?
        if let photoData, let images = services.images {
            newReference = await Task.detached { try? images.save(photoData, in: .wishlist) }.value
            guard newReference != nil else {
                errorMessage = String(localized: "The photo couldn't be stored. Try another photo.")
                return
            }
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = WishlistDraft(
            name: name, estimatedPrice: estimate, priority: priority, status: statusIsEditable ? status : .wanted,
            categoryID: categoryID, notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            targetDate: hasTargetDate ? targetDate : nil)
        do {
            // A retry after a later step failed updates the item already created instead of adding a second one.
            let id: UUID
            if let existing = item?.id ?? createdID {
                try await services.transactions.updateWishlistItem(existing, with: draft, now: .now)
                id = existing
            } else {
                id = try await services.transactions.createWishlistItem(draft, now: .now)
                createdID = id
            }
            if newReference != nil || removePhoto {
                let previous = try await services.transactions.setWishlistMedia(newReference, item: id, now: .now)
                if let previous {
                    try? services.images?.delete(previous)
                }
            }
            dismiss()
        } catch {
            if let newReference {
                try? services.images?.delete(newReference)
            }
            errorMessage = String(localized: "This item couldn't be saved. Check the name, price, and category.")
        }
    }
}
