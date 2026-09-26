import Combine
import HouseholdHubCore
import SwiftData
import SwiftUI

/// Settings › Accounts (Sprint 10 decisions 1-4, 7): each account with its current balance, the default marked; add,
/// edit, make default, archive, and delete while nothing references it. Accounts with history are archived, never
/// deleted, and still count in the household total.
struct AccountsView: View {
    @Environment(\.services) private var services
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @State private var editing: AccountEditorView.Mode?
    @State private var pendingDelete: Account?
    @State private var inUse: Account?
    @State private var balances: HouseholdBalances?
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var defaultID: UUID? { settings.first?.defaultAccountID }
    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var archived: [Account] { accounts.filter(\.isArchived) }

    /// Any context's save, including the service actors', so balances refresh after every write.
    private var storeSaves: some Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)
    }

    var body: some View {
        List {
            Section {
                ForEach(active) { account in
                    row(account)
                }
            } footer: {
                if let total = balances?.household.current {
                    Text("Household total: \(total.formatted())")
                }
            }
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { account in
                        row(account)
                    }
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add account", systemImage: "plus") { editing = .create }
                    .accessibilityIdentifier("accounts.add")
            }
        }
        .sheet(item: $editing) { mode in
            NavigationStack { AccountEditorView(mode: mode) }
        }
        .confirmationDialog(
            "Delete this account?", isPresented: deleteShown, titleVisibility: .visible, presenting: pendingDelete
        ) { account in
            Button("Delete \(account.name)", role: .destructive) { delete(account) }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(deleteMessage(account))
        }
        .confirmationDialog(
            "Account in use", isPresented: inUseShown, titleVisibility: .visible, presenting: inUse
        ) { account in
            Button("Archive \(account.name)") { setArchived(account, true) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Transactions or recurring items use this account. Archive it to keep its history.")
        }
        .task { await refresh() }
        .onReceive(storeSaves) { _ in Task { await refresh() } }
    }

    private func row(_ account: Account) -> some View {
        // At accessibility text sizes the icon goes and the amount moves under the name, so no word or amount is
        // broken across lines (Sprint 10 walk).
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: AccountFormat.icon(account.kind))
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            rowLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                    Text(detail(account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                if let current = balances?.balance(of: account.id)?.current {
                    Text(AccountFormat.balanceText(current, kind: account.kind))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.row")
        .swipeActions(edge: .trailing) {
            if account.id != defaultID {
                Button("Delete") { pendingDelete = account }
                    .tint(.red)
                Button(archiveTitle(account)) { setArchived(account, !account.isArchived) }
                    .tint(.orange)
            }
            Button("Edit") { editing = .edit(account) }
                .tint(.blue)
        }
        .contextMenu { actions(account) }
        .accessibilityActions { actions(account) }
    }

    private var rowLayout: AnyLayout {
        if typeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(spacing: 8))
    }

    @ViewBuilder
    private func actions(_ account: Account) -> some View {
        Button("Edit", systemImage: "pencil") { editing = .edit(account) }
        if account.id != defaultID {
            if !account.isArchived {
                Button("Make Default", systemImage: "star") { makeDefault(account) }
            }
            Button(archiveTitle(account), systemImage: "archivebox") { setArchived(account, !account.isArchived) }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = account }
        }
    }

    private func detail(_ account: Account) -> String {
        let kind = AccountFormat.kindName(account.kind)
        return account.id == defaultID ? kind + " · " + String(localized: "Default") : kind
    }

    /// States what leaves the household total with the account (its starting balance) and that it can't be undone.
    private func deleteMessage(_ account: Account) -> String {
        let consequence: String
        if account.startingBalance.isZero {
            consequence = String(localized: "It has no starting balance, so the household total doesn't change.")
        } else {
            let amount = AccountFormat.balanceText(account.startingBalance, kind: account.kind)
            consequence = String(localized: "Its starting balance (\(amount)) leaves the household total.")
        }
        let rest = String(
            localized: "This can't be undone. An account with transactions can't be deleted; archive it instead.")
        return consequence + " " + rest
    }

    private func archiveTitle(_ account: Account) -> LocalizedStringKey {
        account.isArchived ? "Restore" : "Archive"
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var inUseShown: Binding<Bool> {
        Binding(get: { inUse != nil }, set: { if !$0 { inUse = nil } })
    }

    private func refresh() async {
        guard let services else { return }
        balances = try? await services.transactions.balances(
            now: .now, calendar: HouseholdCalendar(timeZone: .current),
            includePendingInProjection: settings.first?.includePendingInProjection ?? false)
    }

    private func delete(_ account: Account) {
        guard let services else { return }
        let id = account.id
        Task {
            do {
                try await services.transactions.deleteAccount(id)
                await WidgetSync.refresh(services)
                errorMessage = nil
            } catch LedgerError.accountInUse {
                inUse = accounts.first { $0.id == id }
            } catch GoalError.usedByGoals {
                errorMessage = String(
                    localized: "A savings goal uses that account. Change or delete the goal, or archive the account.")
            } catch {
                errorMessage = String(localized: "That account couldn't be deleted.")
            }
        }
    }

    private func setArchived(_ account: Account, _ archived: Bool) {
        guard let services else { return }
        let id = account.id
        Task {
            do {
                try await services.transactions.setAccountArchived(archived, account: id, now: .now)
                await WidgetSync.refresh(services)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That account couldn't be changed.")
            }
        }
    }

    private func makeDefault(_ account: Account) {
        guard let services else { return }
        let id = account.id
        Task {
            do {
                try await services.transactions.setDefaultAccount(id, now: .now)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That account couldn't be made the default.")
            }
        }
    }
}

/// Creates or edits an account. A credit card asks for the amount owed, stored as a negative balance.
struct AccountEditorView: View {
    enum Mode: Identifiable {
        case create
        case edit(Account)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let account): return account.id.uuidString
            }
        }
    }

    let mode: Mode

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @State private var name: String
    @State private var kind: AccountKind
    @State private var balanceText: String
    @State private var asOf: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .bank)
            _balanceText = State(initialValue: "")
            _asOf = State(initialValue: .now)
        case .edit(let account):
            _name = State(initialValue: account.name)
            _kind = State(initialValue: account.kind)
            let shown = (try? account.kind.entered(fromStored: account.startingBalance)) ?? account.startingBalance
            _balanceText = State(initialValue: LedgerFormat.editableAmount(shown))
            _asOf = State(initialValue: account.startingBalanceDate)
        }
    }

    private var currencyCode: String { settings.first?.currencyCode ?? "CAD" }

    /// The signed baseline to store; nil when the text isn't an amount.
    private var startingBalance: Money? {
        let trimmed = balanceText.trimmingCharacters(in: .whitespaces)
        let decimal = trimmed.isEmpty ? Decimal(0) : LedgerFormat.parseDecimal(trimmed)
        guard let decimal, let currency = try? Currency(code: currencyCode),
            let entered = try? Money(decimal: decimal, currency: currency)
        else { return nil }
        return try? kind.stored(fromEntered: entered)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startingBalance != nil && !isSaving
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("accountEditor.name")
                Picker("Kind", selection: $kind) {
                    ForEach(AccountKind.allCases, id: \.self) { kind in
                        Text(AccountFormat.kindName(kind)).tag(kind)
                    }
                }
                .accessibilityIdentifier("accountEditor.kind")
            }
            Section {
                LabeledContent(kind.isLiability ? "Owed" : "Balance") {
                    TextField("0.00", text: $balanceText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("accountEditor.balance")
                }
                DatePicker("As of", selection: $asOf, in: ...Date.now, displayedComponents: .date)
            } header: {
                Text("Starting balance")
            } footer: {
                Text(
                    kind.isLiability
                        ? "What the card owed when this day began. Its transactions are added on top."
                        : "What the account held when this day began. Its transactions are added on top.")
            }
            if let errorMessage {
                ErrorText(errorMessage)
            }
        }
        .navigationTitle(isCreating ? "New Account" : "Edit Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("accountEditor.save")
            }
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private func save() async {
        guard let services, let startingBalance, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let now = Date.now
        let draft = AccountDraft(
            name: name, kind: kind, startingBalance: startingBalance,
            startingBalanceDate: OnboardingView.baselineDate(asOf, now: now))
        do {
            switch mode {
            case .create: try await services.transactions.createAccount(draft, now: now)
            case .edit(let account): try await services.transactions.updateAccount(account.id, with: draft, now: now)
            }
            await WidgetSync.refresh(services)
            dismiss()
        } catch GoalError.usedByGoals {
            errorMessage = String(localized: "A savings goal uses this account, so it can't become a credit card.")
        } catch {
            errorMessage = String(localized: "The account couldn't be saved.")
        }
    }
}

/// Account display rules (Sprint 10 decision 1): a credit card shows what it owes, as a positive "Owed" amount.
enum AccountFormat {
    static func kindName(_ kind: AccountKind) -> String {
        switch kind {
        case .bank: return String(localized: "Bank account")
        case .savings: return String(localized: "Savings")
        case .creditCard: return String(localized: "Credit card")
        case .cash: return String(localized: "Cash")
        }
    }

    static func icon(_ kind: AccountKind) -> String {
        switch kind {
        case .bank: return "building.columns"
        case .savings: return "banknote"
        case .creditCard: return "creditcard"
        case .cash: return "dollarsign.circle"
        }
    }

    /// "Owed $500.00" for a card holding -500; otherwise the signed amount.
    static func balanceText(_ balance: Money, kind: AccountKind) -> String {
        guard kind.isLiability, balance.minorUnits < 0, let owed = try? kind.entered(fromStored: balance) else {
            return balance.formatted()
        }
        return String(localized: "Owed \(owed.formatted())")
    }
}
