import HouseholdHubCore
import SwiftData
import SwiftUI

/// Adds, edits or removes a category's monthly budget (Sprint 11). Rollover is on by default (owner decision 17).
struct BudgetEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(CategoryBudget)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let budget): return budget.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query private var budgets: [CategoryBudget]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @State private var categoryID: UUID?
    @State private var limitText: String
    @State private var rollsOver: Bool
    @State private var isConfirmingRemove = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _categoryID = State(initialValue: nil)
            _limitText = State(initialValue: "")
            _rollsOver = State(initialValue: true)
        case .edit(let budget):
            _categoryID = State(initialValue: budget.categoryID)
            _limitText = State(initialValue: LedgerFormat.editableAmount(budget.limit))
            _rollsOver = State(initialValue: budget.rollsOver)
        }
    }

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }
    private var limit: Money? { LedgerFormat.parseAmount(limitText, currencyCode: currencyCode) }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Active spending categories that don't have a budget yet.
    private var available: [CategoryRecord] {
        let taken = Set(budgets.map(\.categoryID))
        return categories.filter { !$0.isArchived && $0.kind.allows(.expense) && !taken.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                if isEditing {
                    LabeledContent("Category", value: categories.first { $0.id == categoryID }?.name ?? "")
                } else {
                    Picker("Category", selection: $categoryID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(available) { category in
                            Text(category.name).tag(UUID?.some(category.id))
                        }
                    }
                    .accessibilityIdentifier("budgetEditor.category")
                }
                FocusingRow("Monthly limit") {
                    TextField("0.00", text: $limitText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("budgetEditor.limit")
                }
                Toggle("Roll over", isOn: $rollsOver)
                    .accessibilityIdentifier("budgetEditor.rollsOver")
            } footer: {
                if rollsOver {
                    Text(
                        """
                        What's left at the end of a month adds to the next one; an overspend takes from it. Turning \
                        this back on starts counting again this month.
                        """
                    )
                } else {
                    Text("Each month starts again at the limit.")
                }
            }
            if isEditing {
                Section {
                    Button("Remove Budget", role: .destructive) { isConfirmingRemove = true }
                        .accessibilityIdentifier("budgetEditor.remove")
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle(isEditing ? "Edit Budget" : "New Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(limit == nil || categoryID == nil || isSaving)
                    .accessibilityIdentifier("budgetEditor.save")
            }
        }
        .confirmationDialog("Remove this budget?", isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove Budget", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its rolled-over amount is lost. Transactions are not changed.")
        }
    }

    private func save() async {
        guard let services, let limit, let categoryID, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await services.categories.setBudget(
                for: categoryID, limit: limit, rollsOver: rollsOver, now: .now,
                calendar: HouseholdCalendar(timeZone: .current))
            dismiss()
        } catch LedgerError.nonPositiveAmount {
            errorMessage = String(localized: "Enter a limit above zero.")
        } catch LedgerError.amountTooLarge {
            errorMessage = String(localized: "That limit is too large.")
        } catch LedgerError.archivedCategory {
            errorMessage = String(localized: "That category is archived. Restore it to budget for it.")
        } catch LedgerError.categoryKindMismatch {
            errorMessage = String(localized: "Only spending categories can have a budget.")
        } catch {
            errorMessage = String(localized: "The budget couldn't be saved.")
        }
    }

    private func remove() async {
        guard let services, let categoryID else { return }
        do {
            try await services.categories.removeBudget(for: categoryID)
            dismiss()
        } catch {
            errorMessage = String(localized: "The budget couldn't be removed.")
        }
    }
}
