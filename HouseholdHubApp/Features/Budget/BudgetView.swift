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
    /// Sprint 23 (A-005): the search the list applies. It trails the typed text by a short pause, so typing stays
    /// responsive with a long history.
    @State private var appliedSearch = ""
    /// Sprint 23 (A-014): the search field is active, so the floating + would sit over its results.
    @State private var isSearching = false
    /// Sprint 23 (A-007): the transaction list's Select mode.
    @State private var isSelecting = false
    /// Sprint 23 (F3): the Undo banner after a delete or bulk edit in Transactions.
    @State private var undoCenter = UndoCenter()
    /// Sprint 23 (F6): searches saved on this device, listed at the top of the filter menu.
    @State private var savedSearches = SavedSearches.store.all()
    @State private var isShowingMoreFilters = false
    @State private var isManagingSearches = false
    @State private var isNamingSearch = false
    @State private var newSearchName = ""
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            Group {
                switch router.budgetSegment {
                case .transactions:
                    TransactionListView(filter: router.budgetFilter, search: appliedSearch, isSelecting: $isSelecting)
                        .environment(undoCenter)
                        .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search transactions")
                        .refreshable { isPresentingQuickAdd = true }
                        .task(id: searchText) { await applySearch(searchText) }
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
            // Recurring and Budgets add with their own + (A-013); searching and selecting need the space (A-014);
            // an Undo banner sits where the button would (Sprint 23 hand check).
            .quickAddAccess(
                showsButton: router.budgetSegment == .transactions && !isSearching && !isSelecting
                    && undoCenter.banner == nil)
            .navigationTitle("Budget")
            .themedScreen(decorated: true, toolbarTrailing: true)
            .toolbar {
                if router.budgetSegment == .transactions {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isSelecting.toggle()
                        } label: {
                            isSelecting ? Text("Done") : Text("Select")
                        }
                        .accessibilityIdentifier("transactions.select")
                    }
                    // Transfers need two accounts (Sprint 10 decision 8).
                    if !isSelecting, accounts.filter({ !$0.isArchived }).count > 1 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("New transfer", systemImage: "arrow.left.arrow.right") {
                                isPresentingTransfer = true
                            }
                            .accessibilityIdentifier("budget.newTransfer")
                        }
                    }
                    if !isSelecting {
                        ToolbarItem(placement: .topBarTrailing) { filterMenu(filter: $router.budgetFilter) }
                    }
                }
            }
            .onChange(of: router.budgetSegment) {
                isSelecting = false
                isSearching = false
            }
            .sheet(isPresented: $isPresentingQuickAdd) { QuickAddView() }
            .sheet(isPresented: $isPresentingTransfer) {
                NavigationStack { TransferEditorView() }
            }
            .sheet(isPresented: $isShowingMoreFilters) {
                NavigationStack {
                    MoreFiltersView(filter: $router.budgetFilter, currencyCode: currencyCode)
                }
            }
            .sheet(isPresented: $isManagingSearches) {
                NavigationStack { SavedSearchesView(searches: $savedSearches) }
                    .presentationDetents([.medium, .large])
            }
            .alert("Save search", isPresented: $isNamingSearch) {
                TextField("Name", text: $newSearchName)
                    .accessibilityIdentifier("savedSearch.name")
                Button("Save") { saveSearch() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Keeps the search text and filters under this name, on this iPhone.")
            }
        }
    }

    /// The household currency, which amount filters are typed in.
    private var currencyCode: String {
        settings.first?.currencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }

    /// Picking a period replaces custom dates set in More filters (Sprint 23, F6).
    private func periodBinding(_ filter: Binding<TransactionFilter>) -> Binding<TransactionFilter.Period> {
        Binding(
            get: { filter.wrappedValue.period },
            set: { period in
                filter.wrappedValue.period = period
                filter.wrappedValue.dateRange = nil
            })
    }

    private func filterMenu(filter: Binding<TransactionFilter>) -> some View {
        Menu {
            // Sprint 23 (F6): saved searches first, each re-applying its text and filters.
            if !savedSearches.isEmpty {
                Section("Saved searches") {
                    ForEach(savedSearches) { saved in
                        Button(saved.name, systemImage: "bookmark") { apply(saved) }
                    }
                }
            }
            // Near the top: the pickers below can make the menu long.
            Section {
                Button("More filters…", systemImage: "slider.horizontal.3") { isShowingMoreFilters = true }
                if filter.wrappedValue.isActive || !searchText.isEmpty {
                    Button("Save search…", systemImage: "bookmark") {
                        newSearchName = ""
                        isNamingSearch = true
                    }
                }
                if !savedSearches.isEmpty {
                    Button("Saved searches…", systemImage: "list.bullet") { isManagingSearches = true }
                }
            }
            Picker("Period", selection: periodBinding(filter)) {
                Text("All time").tag(TransactionFilter.Period.all)
                Text("This week").tag(TransactionFilter.Period.thisWeek)
                Text("This month").tag(TransactionFilter.Period.thisMonth)
                Text("Last 30 days").tag(TransactionFilter.Period.last30Days)
            }
            Picker("Category", selection: filter.categoryChoice) {
                Text("All categories").tag(TransactionFilter.CategoryChoice.all)
                // Sprint 23 (A-006): what still needs a category, such as rows from an import.
                Text("Uncategorized").tag(TransactionFilter.CategoryChoice.uncategorized)
                ForEach(categories) { category in
                    Text(category.name).tag(TransactionFilter.CategoryChoice.category(category.id))
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

    /// Keeps the current search text and filter under the typed name; an existing name is replaced.
    private func saveSearch() {
        SavedSearches.store.save(name: newSearchName, text: searchText, filter: router.budgetFilter)
        savedSearches = SavedSearches.store.all()
    }

    /// Re-applies a saved search: its filter, and its text straight away, without the typing pause.
    private func apply(_ saved: SavedSearch) {
        router.budgetFilter = saved.filter
        searchText = saved.text
        appliedSearch = saved.text
    }

    /// Hands the typed search to the list after a short pause; a newer keystroke cancels the wait. Clearing the field
    /// applies at once.
    private func applySearch(_ text: String) async {
        if !text.isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
        }
        appliedSearch = text
    }
}

#Preview {
    BudgetView()
        .environment(AppRouter())
}
