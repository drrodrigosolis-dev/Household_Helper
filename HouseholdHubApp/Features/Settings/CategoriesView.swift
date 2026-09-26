import HouseholdHubCore
import SwiftData
import SwiftUI

/// Category management (spec §7.3, §8.4): add, edit, archive, and reassign. Referenced categories are never deleted.
struct CategoriesView: View {
    @Environment(\.services) private var services
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
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
        } message: { _ in
            Text("If anything uses it you'll be offered archive or move instead. Deleting can't be undone.")
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
            Text("\(info.count) items use this category. Archive it to keep history, or move them first.")
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
        Task { try? await services.categories.setArchived(archived, category: id, now: .now) }
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
                try await services.categories.reassign(from: source, to: destination, now: .now)
            } catch {
                errorMessage = String(localized: "Items couldn't be moved to that category.")
                return
            }
            do {
                try await services.categories.delete(category: source)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "Items were moved, but the old category couldn't be deleted.")
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
                            .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
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
                            .accessibilityLabel(token.hex)
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
