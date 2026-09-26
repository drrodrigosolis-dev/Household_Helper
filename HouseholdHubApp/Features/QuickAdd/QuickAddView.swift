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

/// Quick Add access on a tab's root screen (spec §24.3): the floating button, bottom scroll clearance so it never
/// covers the last row, and the sheet. Pushed screens (editors, Settings pages) do not get the button.
private struct QuickAddAccess: ViewModifier {
    @State private var isPresenting = false

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, 88, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                QuickAddButton { isPresenting = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
            }
            .sheet(isPresented: $isPresenting) { QuickAddView() }
    }
}

extension View {
    func quickAddAccess() -> some View {
        modifier(QuickAddAccess())
    }
}

/// Quick Add sheet (spec §24.3): one autofocused field parsed by the §25 grammar, progressive details, and a
/// Save button that stays disabled until the draft is valid. The Wishlist segment turns the same text into a
/// wishlist item: the amount becomes the estimated price and the description the name. The Task segment makes a
/// task: the description becomes the title and a date word ("tomorrow") the due date.
struct QuickAddView: View {
    enum Entry: Hashable {
        case expense
        case income
        case wishlist
        case task
    }

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    @State private var text = ""
    @State private var entry = Entry.expense
    @State private var amountText = ""
    @State private var categoryID: UUID?
    @State private var occurredAt = Date.now
    @State private var hasDueDate = false
    @State private var dueFromText = false
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
    private var type: TransactionType { entry == .income ? .income : .expense }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespaces) }

    /// A wishlist item needs a name; its price may be left empty (unknown) but not malformed.
    private var canSave: Bool {
        guard !isSaving else { return false }
        if entry == .task {
            return !trimmedNotes.isEmpty
        }
        if entry == .wishlist {
            let priceIsValid = amountText.trimmingCharacters(in: .whitespaces).isEmpty || amount != nil
            return !trimmedNotes.isEmpty && priceIsValid
        }
        return amount != nil
    }

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
                    Picker("Type", selection: $entry) {
                        Text("Expense").tag(Entry.expense)
                        Text("Income").tag(Entry.income)
                        Text("Wishlist").tag(Entry.wishlist)
                        Text("Task").tag(Entry.task)
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
                        .disabled(!canSave)
                        .accessibilityIdentifier("quickadd.save")
                }
            }
            .onChange(of: text) { applyParse() }
            .onAppear { quickFieldFocused = true }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            if entry == .task {
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $occurredAt, displayedComponents: .date)
                }
            } else {
                LabeledContent(amountLabel) {
                    TextField(amountPrompt, text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("quickadd.amount")
                }
                Picker("Category", selection: $categoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(usableCategories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            }
            if entry == .expense || entry == .income {
                DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
            }
            LabeledContent(notesLabel) {
                TextField("Optional", text: $notes)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("quickadd.notes")
            }
        }
    }

    private var amountLabel: LocalizedStringKey { entry == .wishlist ? "Estimated price" : "Amount" }
    private var amountPrompt: LocalizedStringKey { entry == .wishlist ? "Optional" : "0.00" }
    private var notesLabel: LocalizedStringKey {
        switch entry {
        case .wishlist: "Name"
        case .task: "Title"
        case .expense, .income: "Notes"
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
        let now = Date.now
        let parsed = parser.parse(text, now: now)
        // Wishlist and Task are explicit choices; a leading "+" only switches between Expense and Income.
        if parsed.type == .income, entry == .expense || entry == .income {
            entry = .income
            typeFromText = true
        } else if typeFromText, entry == .income {
            entry = .expense
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
        // A date word moved the date away from now: for a task that is the due date.
        if parsed.occurredAt != now {
            hasDueDate = true
            dueFromText = true
        } else if dueFromText {
            hasDueDate = false
            dueFromText = false
        }
        notes = parsed.description
    }

    private func save() async {
        guard let services, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        if entry == .wishlist {
            await saveWishlistItem(services)
            return
        }
        if entry == .task {
            await saveTask(services)
            return
        }
        guard let amount else { return }
        if let categoryID, let category = categories.first(where: { $0.id == categoryID }),
            !category.kind.allows(type)
        {
            errorMessage = String(localized: "\(category.name) can't be used for this type. Choose another category.")
            return
        }
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

    private func saveWishlistItem(_ services: AppServices) async {
        let price = amount ?? Money(minorUnits: 0, currencyCode: currencyCode)
        let category = categories.first { $0.id == categoryID && $0.kind.allows(.expense) }
        let draft = WishlistDraft(name: trimmedNotes, estimatedPrice: price, categoryID: category?.id)
        do {
            try await services.transactions.createWishlistItem(draft, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "This couldn't be saved. Check the name and price.")
        }
    }

    private func saveTask(_ services: AppServices) async {
        let due = hasDueDate ? HouseholdCalendar(timeZone: .current).startOfDay(for: occurredAt) : nil
        let draft = TaskDraft(title: trimmedNotes, dueDate: due)
        do {
            try await services.board.createTask(draft, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "This couldn't be saved. Check the title.")
        }
    }
}
