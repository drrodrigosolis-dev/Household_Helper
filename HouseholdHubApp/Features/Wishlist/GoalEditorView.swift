import HouseholdHubCore
import SwiftData
import SwiftUI

/// Adds or edits a savings goal (Sprint 12): a name, a target, the account whose balance counts, an optional date and
/// an optional wishlist item. Editing also archives, restores or deletes it.
struct GoalEditorView: View {
    enum Mode: Identifiable {
        /// A new goal, prefilled from a wishlist item when started from its detail.
        case create(wishlistItem: WishlistItem?)
        case edit(SavingsGoal)

        var id: String {
            switch self {
            case .create(let item): return "create-\(item?.id.uuidString ?? "")"
            case .edit(let goal): return goal.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \WishlistItem.createdAt, order: .reverse) private var items: [WishlistItem]
    @Query private var goals: [SavingsGoal]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @State private var name: String
    @State private var targetText: String
    @State private var accountID: UUID?
    @State private var hasDate: Bool
    @State private var targetDate: Date
    @State private var wishlistItemID: UUID?
    @State private var isConfirmingDelete = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        let nextYear = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        switch mode {
        case .create(let item):
            _name = State(initialValue: item?.name ?? "")
            let estimate = item?.estimatedPrice
            _targetText = State(
                initialValue: estimate.map { $0.minorUnits > 0 ? LedgerFormat.editableAmount($0) : "" } ?? "")
            _accountID = State(initialValue: nil)
            _hasDate = State(initialValue: item?.targetDate != nil)
            _targetDate = State(initialValue: item?.targetDate ?? nextYear)
            _wishlistItemID = State(initialValue: item?.id)
        case .edit(let goal):
            _name = State(initialValue: goal.name)
            _targetText = State(initialValue: LedgerFormat.editableAmount(goal.target))
            _accountID = State(initialValue: goal.accountID)
            _hasDate = State(initialValue: goal.targetDate != nil)
            _targetDate = State(initialValue: goal.targetDate ?? nextYear)
            _wishlistItemID = State(initialValue: goal.wishlistItemID)
        }
    }

    private var editing: SavingsGoal? {
        if case .edit(let goal) = mode { return goal }
        return nil
    }

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }
    private var target: Money? { LedgerFormat.parseAmount(targetText, currencyCode: currencyCode) }

    /// Accounts that hold money (not credit cards); archived ones only if the goal already uses one.
    private var eligibleAccounts: [Account] {
        accounts.filter { !$0.kind.isLiability && (!$0.isArchived || $0.id == editing?.accountID) }
    }

    /// The picked account, else the default account when it holds money, else the first one that does.
    private var chosenAccountID: UUID? {
        if let accountID { return accountID }
        let eligible = eligibleAccounts
        if let main = settings.first?.defaultAccountID, eligible.contains(where: { $0.id == main }) { return main }
        return eligible.first?.id
    }

    /// Wishlist items still wanted that no other goal uses, plus the one this goal has.
    private var linkableItems: [WishlistItem] {
        let taken = Set(goals.filter { $0.id != editing?.id }.compactMap(\.wishlistItemID))
        return items.filter {
            $0.id == wishlistItemID || (!taken.contains($0.id) && ($0.status == .wanted || $0.status == .pending))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("goalEditor.name")
                LabeledContent("Target") {
                    TextField("0.00", text: $targetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("goalEditor.target")
                }
                Picker("Account", selection: accountBinding) {
                    ForEach(eligibleAccounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                .accessibilityIdentifier("goalEditor.account")
            } footer: {
                Text("Progress is this account's current balance. Credit cards can't hold a goal.")
            }
            Section {
                Toggle("Target date", isOn: $hasDate)
                    .accessibilityIdentifier("goalEditor.hasDate")
                if hasDate {
                    DatePicker("Reach by", selection: $targetDate, displayedComponents: .date)
                        .accessibilityIdentifier("goalEditor.date")
                }
            } footer: {
                if hasDate {
                    Text("Shows what to save each month to get there on time.")
                }
            }
            Section {
                Picker("Wishlist item", selection: $wishlistItemID) {
                    Text("None").tag(UUID?.none)
                    ForEach(linkableItems) { item in
                        Text(item.name).tag(UUID?.some(item.id))
                    }
                }
                .accessibilityIdentifier("goalEditor.wishlistItem")
            }
            if let goal = editing {
                Section {
                    if goal.isArchived {
                        Button("Restore Goal") { Task { await setArchived(false, goal) } }
                            .accessibilityIdentifier("goalEditor.archive")
                    } else {
                        Button("Archive Goal") { Task { await setArchived(true, goal) } }
                            .accessibilityIdentifier("goalEditor.archive")
                    }
                    Button("Delete Goal", role: .destructive) { isConfirmingDelete = true }
                        .accessibilityIdentifier("goalEditor.delete")
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle(editing == nil ? "New Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(target == nil || chosenAccountID == nil || isSaving)
                    .accessibilityIdentifier("goalEditor.save")
            }
        }
        .confirmationDialog("Delete this goal?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its account, balance and wishlist item are not changed.")
        }
    }

    private var accountBinding: Binding<UUID?> {
        Binding(get: { chosenAccountID }, set: { accountID = $0 })
    }

    private func save() async {
        guard let services, let target, let account = chosenAccountID, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let draft = GoalDraft(
            name: name, target: target, accountID: account, targetDate: hasDate ? targetDate : nil,
            wishlistItemID: wishlistItemID)
        do {
            if let goal = editing {
                try await services.transactions.updateGoal(goal.id, with: draft, now: .now)
            } else {
                try await services.transactions.createGoal(draft, now: .now)
            }
            dismiss()
        } catch GoalError.emptyName {
            errorMessage = String(localized: "Give the goal a name.")
        } catch LedgerError.nonPositiveAmount {
            errorMessage = String(localized: "Enter a target above zero.")
        } catch LedgerError.amountTooLarge {
            errorMessage = String(localized: "That target is too large.")
        } catch LedgerError.archivedAccount {
            errorMessage = String(localized: "That account is archived. Restore it to save towards it.")
        } catch GoalError.wishlistItemNotWanted {
            errorMessage = String(localized: "Only a wishlist item still wanted can get a goal.")
        } catch GoalError.liabilityAccount {
            errorMessage = String(localized: "Pick an account that holds money, not a credit card.")
        } catch GoalError.wishlistItemHasGoal {
            errorMessage = String(localized: "That wishlist item already has a goal.")
        } catch {
            errorMessage = String(localized: "The goal couldn't be saved.")
        }
    }

    private func setArchived(_ archived: Bool, _ goal: SavingsGoal) async {
        guard let services else { return }
        do {
            try await services.transactions.setGoalArchived(archived, goal: goal.id, now: .now)
            dismiss()
        } catch {
            errorMessage = String(localized: "The goal couldn't be changed.")
        }
    }

    private func delete() async {
        guard let services, let goal = editing else { return }
        do {
            try await services.transactions.deleteGoal(goal.id)
            dismiss()
        } catch {
            errorMessage = String(localized: "The goal couldn't be deleted.")
        }
    }
}
