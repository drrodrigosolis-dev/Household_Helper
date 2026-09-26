import HouseholdHubCore
import SwiftData
import SwiftUI

/// Budget tab (spec §24.2): Transactions / Recurring segments; transactions filtered by period, category, status.
struct BudgetView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case transactions
        case recurring
        /// Category budgets (Sprint 11).
        case budgets

        var id: String { rawValue }
    }

    @Environment(AppRouter.self) private var router
    @State private var isPresentingQuickAdd = false
    @State private var isPresentingTransfer = false
    /// Sprint 14: searches the transactions the filter allows.
    @State private var searchText = ""
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            Group {
                switch router.budgetSegment {
                case .transactions:
                    TransactionListView(filter: router.budgetFilter, search: searchText)
                        .searchable(text: $searchText, prompt: "Search transactions")
                        .refreshable { isPresentingQuickAdd = true }
                case .recurring:
                    RecurringListView()
                case .budgets:
                    BudgetsListView()
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("View", selection: $router.budgetSegment) {
                    Text("Transactions").tag(Segment.transactions)
                    Text("Recurring").tag(Segment.recurring)
                    Text("Budgets").tag(Segment.budgets)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityIdentifier("budget.segment")
            }
            .quickAddAccess()
            .navigationTitle("Budget")
            .toolbar {
                if router.budgetSegment == .transactions {
                    // Transfers need two accounts (Sprint 10 decision 8).
                    if accounts.filter({ !$0.isArchived }).count > 1 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("New transfer", systemImage: "arrow.left.arrow.right") {
                                isPresentingTransfer = true
                            }
                            .accessibilityIdentifier("budget.newTransfer")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { filterMenu(filter: $router.budgetFilter) }
                }
            }
            .sheet(isPresented: $isPresentingQuickAdd) { QuickAddView() }
            .sheet(isPresented: $isPresentingTransfer) {
                NavigationStack { TransferEditorView() }
            }
        }
    }

    private func filterMenu(filter: Binding<TransactionFilter>) -> some View {
        Menu {
            Picker("Period", selection: filter.period) {
                Text("All time").tag(TransactionFilter.Period.all)
                Text("This week").tag(TransactionFilter.Period.thisWeek)
                Text("This month").tag(TransactionFilter.Period.thisMonth)
                Text("Last 30 days").tag(TransactionFilter.Period.last30Days)
            }
            Picker("Category", selection: filter.categoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            if accounts.count > 1 {
                Picker("Account", selection: filter.accountID) {
                    Text("All accounts").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
            }
            Picker("Status", selection: filter.status) {
                Text("Any status").tag(TransactionStatus?.none)
                ForEach(TransactionStatus.allCases, id: \.self) { status in
                    Text(LedgerFormat.statusLabel(status)).tag(TransactionStatus?.some(status))
                }
            }
            if filter.wrappedValue.isActive {
                Button("Clear filters", role: .destructive) { filter.wrappedValue = TransactionFilter() }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .symbolVariant(filter.wrappedValue.isActive ? .fill : .none)
        }
        .accessibilityValue(filter.wrappedValue.isActive ? Text("On") : Text("Off"))
        .accessibilityIdentifier("budget.filter")
    }
}

#Preview {
    BudgetView()
        .environment(AppRouter())
}
