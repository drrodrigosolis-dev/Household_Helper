import HouseholdHubCore
import SwiftData
import SwiftUI

/// Category management (spec §7.3, §8.4): add, edit, archive, and reassign. Referenced categories are never deleted.
struct CategoriesView: View {
    @Environment(\.services) private var services
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query private var budgets: [CategoryBudget]
    @State private var editing: CategoryEditorView.Mode?
    @State private var inUse: InUse?
    @State private var pendingDelete: CategoryRecord?
    @State private var errorMessage: String?

    struct InUse: Identifiable {
        let category: CategoryRecord
        let count: Int
        var id: UUID { category.id }
    }

    private var active: [CategoryRecord] { categories.filter { !$0.isArchived } }
    private var archived: [CategoryRecord] { categories.filter(\.isArchived) }

    var body: some View {
        List {
            Section("Active") {
                ForEach(active) { category in
                    row(category)
                }
            }
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { category in
                        row(category)
                    }
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add category", systemImage: "plus") { editing = .create }
                    .accessibilityIdentifier("categories.add")
            }
        }
        .sheet(item: $editing) { mode in
            CategoryEditorView(mode: mode)
        }
        .confirmationDialog(
            "Delete this category?", isPresented: deleteShown, titleVisibility: .visible, presenting: pendingDelete
        ) { category in
            Button("Delete \(category.name)", role: .destructive) { delete(category) }
            Button("Cancel", role: .cancel) {}
        } message: { category in
            Text(deleteMessage(category))
        }
        .confirmationDialog(
            "Category in use", isPresented: inUseShown, titleVisibility: .visible, presenting: inUse
        ) { info in
            Button("Archive \(info.category.name)") { setArchived(info.category, true) }
            ForEach(reassignTargets(for: info.category)) { target in
                Button("Move to \(target.name) and delete") { reassign(info.category, to: target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { info in
            Text(inUseMessage(info))
        }
    }

    private func row(_ category: CategoryRecord) -> some View {
        HStack(spacing: 12) {
            CategoryBadge(icon: category.icon, color: category.color)
            VStack(alignment: .leading) {
                Text(category.name)
                Text(kindLabel(category.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("category.row")
        .swipeActions(edge: .trailing) {
            if !category.isSystem {
                Button("Delete", role: .destructive) { pendingDelete = category }
            }
            Button(archiveTitle(category)) { setArchived(category, !category.isArchived) }
                .tint(.orange)
            Button("Edit") { editing = .edit(category) }
                .tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = .edit(category) }
            Button(archiveTitle(category), systemImage: "archivebox") {
                setArchived(category, !category.isArchived)
            }
            if !category.isSystem {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = category }
            }
        }
    }

    private func hasBudget(_ id: UUID) -> Bool {
        budgets.contains { $0.categoryID == id }
    }

    /// Deleting also removes the category's budget (Sprint 11), and says so.
    private func deleteMessage(_ category: CategoryRecord) -> String {
        let base = String(localized: "If anything uses it you'll be offered archive or move instead.")
        let budget = hasBudget(category.id) ? " " + String(localized: "Its monthly budget is removed too.") : ""
        return base + budget + " " + String(localized: "Deleting can't be undone.")
    }

    /// Moving spending into a category with a budget changes that budget's past months and rollover; say so.
    private func inUseMessage(_ info: InUse) -> String {
        var parts = [
            String(localized: "\(info.count) items use this category. Archive it to keep history, or move them first.")
        ]
        if hasBudget(info.category.id) {
            parts.append(String(localized: "Moving and deleting removes its monthly budget."))
        }
        if reassignTargets(for: info.category).contains(where: { hasBudget($0.id) }) {
            parts.append(
                String(
                    localized: "Moved spending counts in the new category's budget, including months already past."))
        }
        return parts.joined(separator: " ")
    }

    private func archiveTitle(_ category: CategoryRecord) -> LocalizedStringKey {
        category.isArchived ? "Restore" : "Archive"
    }

    private func kindLabel(_ kind: CategoryKind) -> LocalizedStringKey {
        switch kind {
        case .expense: return "Expense"
        case .income: return "Income"
        case .both: return "Income and expense"
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var inUseShown: Binding<Bool> {
        Binding(get: { inUse != nil }, set: { if !$0 { inUse = nil } })
    }

    private func reassignTargets(for category: CategoryRecord) -> [CategoryRecord] {
        active.filter { $0.id != category.id && ($0.kind == category.kind || $0.kind == .both) }
    }

    private func setArchived(_ category: CategoryRecord, _ archived: Bool) {
        guard let services else { return }
        let id = category.id
        Task {
            do {
                try await services.categories.setArchived(archived, category: id, now: .now)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That category couldn't be changed.")
            }
        }
    }

    private func delete(_ category: CategoryRecord) {
        guard let services else { return }
        let id = category.id
        Task {
            do {
                try await services.categories.delete(category: id)
                errorMessage = nil
            } catch LedgerError.categoryInUse(let count) {
                inUse = InUse(category: category, count: count)
            } catch {
                errorMessage = String(localized: "This category can't be deleted.")
            }
        }
    }

    private func reassign(_ category: CategoryRecord, to target: CategoryRecord) {
        guard let services else { return }
        let source = category.id
        let destination = target.id
        Task {
            do {
                try await services.categories.reassignAndDelete(from: source, to: destination, now: .now)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "Items couldn't be moved to that category. Nothing was changed.")
            }
        }
    }
}

/// Add or edit a category: name, kind, icon, and a color from a contrast-checked palette.
struct CategoryEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(CategoryRecord)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let category): return category.id.uuidString
            }
        }
    }

    static let icons = [
        "cart",
        "fork.knife",
        "house",
        "bolt",
        "car",
        "cross.case",
        "film",
        "bag",
        "gift",
        "pawprint",
        "book",
        "gamecontroller",
        "airplane",
        "cup.and.saucer",
        "tshirt",
        "wrench.and.screwdriver",
        "briefcase",
        "plus.circle",
        "heart",
        "ellipsis.circle",
    ]
    static let palette = SystemCategory.defaults.map(\.color)

    /// Spoken names for the palette and icons; VoiceOver would otherwise read hex codes and symbol names.
    static func colorName(_ token: ColorToken) -> String {
        switch token.hex {
        case "#2E7D32FF": String(localized: "Green")
        case "#C62828FF": String(localized: "Red")
        case "#1565C0FF": String(localized: "Blue")
        case "#EF6C00FF": String(localized: "Orange")
        case "#6A1B9AFF": String(localized: "Purple")
        case "#AD1457FF": String(localized: "Pink")
        case "#00838FFF": String(localized: "Teal")
        case "#4527A0FF": String(localized: "Indigo")
        case "#546E7AFF": String(localized: "Slate")
        case "#00695CFF": String(localized: "Dark teal")
        case "#558B2FFF": String(localized: "Olive")
        default: token.hex
        }
    }

    static func iconName(_ symbol: String) -> String {
        switch symbol {
        case "cart": String(localized: "Shopping cart")
        case "fork.knife": String(localized: "Dining")
        case "house": String(localized: "House")
        case "bolt": String(localized: "Electricity")
        case "car": String(localized: "Car")
        case "cross.case": String(localized: "First aid")
        case "film": String(localized: "Film")
        case "bag": String(localized: "Bag")
        case "gift": String(localized: "Gift")
        case "pawprint": String(localized: "Pets")
        case "book": String(localized: "Book")
        case "gamecontroller": String(localized: "Games")
        case "airplane": String(localized: "Travel")
        case "cup.and.saucer": String(localized: "Coffee")
        case "tshirt": String(localized: "Clothing")
        case "wrench.and.screwdriver": String(localized: "Repairs")
        case "briefcase": String(localized: "Work")
        case "plus.circle": String(localized: "Plus")
        case "heart": String(localized: "Heart")
        case "ellipsis.circle": String(localized: "Other")
        default: symbol.replacingOccurrences(of: ".", with: " ")
        }
    }

    let mode: Mode
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: CategoryKind
    @State private var icon: String
    @State private var color: ColorToken
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .expense)
            _icon = State(initialValue: CategoryEditorView.icons[0])
            _color = State(initialValue: CategoryEditorView.palette.first ?? .black)
        case .edit(let category):
            _name = State(initialValue: category.name)
            _kind = State(initialValue: category.kind)
            _icon = State(initialValue: category.icon)
            _color = State(initialValue: category.color)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("categoryEditor.name")
                    Picker("Used for", selection: $kind) {
                        Text("Expenses").tag(CategoryKind.expense)
                        Text("Income").tag(CategoryKind.income)
                        Text("Both").tag(CategoryKind.both)
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(CategoryEditorView.icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                CategoryBadge(icon: symbol, color: symbol == icon ? color : nil)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(CategoryEditorView.iconName(symbol))
                            .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                        }
                    }
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(CategoryEditorView.palette, id: \.self) { token in
                            Button {
                                color = token
                            } label: {
                                Circle()
                                    .fill(Color(token))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(.primary, lineWidth: token == color ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(CategoryEditorView.colorName(token))
                            .accessibilityAddTraits(token == color ? .isSelected : [])
                        }
                    }
                }
                if let errorMessage {
                    ErrorText(errorMessage)
                }
            }
            .navigationTitle(isCreating ? Text("New Category") : Text("Edit Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("categoryEditor.save")
                }
            }
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private func save() async {
        guard let services, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                try await services.categories.create(name: name, icon: icon, color: color, kind: kind, now: .now)
            case .edit(let category):
                try await services.categories.update(
                    category: category.id, name: name, icon: icon, color: color, kind: kind, now: .now)
            }
            dismiss()
        } catch LedgerError.categoryKindMismatch {
            errorMessage = String(localized: "Existing items in this category don't fit that choice.")
        } catch {
            errorMessage = String(localized: "The category couldn't be saved.")
        }
    }
}
