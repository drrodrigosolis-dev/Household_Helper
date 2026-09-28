import HouseholdHubCore
import SwiftData
import SwiftUI
import TipKit

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

    /// The floating Quick Add button: Recurring and Budgets add with their own + (A-013); searching and selecting need
    /// the space (A-014); an Undo banner sits where the button would (Sprint 23 hand check).
    private var showsQuickAddButton: Bool {
        router.budgetSegment == .transactions && !isSearching && !isSelecting && undoCenter.banner == nil
    }

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
                        // Sprint 23 hand check: a custom date or amount range had no visible sign once set from the
                        // filter menu or from Analytics (A-018); a removable chip says which is active.
                        .safeAreaInset(edge: .top) { activeFilterChips(filter: $router.budgetFilter) }
                case .recurring:
                    RecurringListView()
                case .budgets:
                    BudgetsListView()
                }
            }
            .tourTarget(.budgetList)
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
            .quickAddAccess(showsButton: showsQuickAddButton)
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
                        // An explicit buttonStyle (iOS 26: a toolbar Button with none can fail to show its popover).
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("transactions.select")
                        .popoverTip(BulkSelectTip())
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
            // Sprint 24: Bulk select sits on a control visible from the first look at Transactions, so its tip waits
            // for a second visit rather than competing with the first-run tour.
            .task(id: router.budgetSegment) {
                if router.budgetSegment == .transactions {
                    await BulkSelectTip.screenSeen.donate()
                }
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

    private let calendar = HouseholdCalendar(timeZone: .current)

    /// Any date range, amount range or search narrows the list beyond a plain period/category/status choice, so
    /// there is something for "Clear All Filters" to earn its place over (Sprint 23 hand check).
    private func hasAnyFilter(_ filter: TransactionFilter) -> Bool {
        filter.isActive || !searchText.isEmpty
    }

    /// Picking a period replaces custom dates set in More filters (Sprint 23, F6). While a custom date range is
    /// active, no preset reads as selected: the menu shows a non-editable "Custom" row ticked instead of the
    /// misleading "All time" (Sprint 23 hand check, after Analytics' A-018 opens Budget with its own range).
    private func periodBinding(_ filter: Binding<TransactionFilter>) -> Binding<TransactionFilter.Period?> {
        Binding(
            get: { filter.wrappedValue.dateRange == nil ? filter.wrappedValue.period : nil },
            set: { period in
                guard let period else { return }
                filter.wrappedValue.period = period
                filter.wrappedValue.dateRange = nil
            })
    }

    /// "Sep 1 – Sep 28": the range's first and last included day, in the household calendar.
    private func dateRangeLabel(_ range: DateInterval) -> String {
        let lastDay = calendar.calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.start
        let start = range.start.formatted(.dateTime.month(.abbreviated).day())
        let end = lastDay.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "\(start) – \(end)")
    }

    /// "$10.00 – $25.00", "≥ $10.00" or "≤ $25.00"; nil when neither bound is set.
    private func amountRangeLabel(_ filter: TransactionFilter) -> String? {
        let format: (Int64) -> String = { Money(minorUnits: $0, currencyCode: self.currencyCode).formatted() }
        switch (filter.minimumAmountMinorUnits, filter.maximumAmountMinorUnits) {
        case let (minimum?, maximum?): return String(localized: "\(format(minimum)) – \(format(maximum))")
        case let (minimum?, nil): return String(localized: "≥ \(format(minimum))")
        case let (nil, maximum?): return String(localized: "≤ \(format(maximum))")
        case (nil, nil): return nil
        }
    }

    /// A removable chip per active date/amount range (spec §24.2 filter chips), plus Clear All Filters once anything
    /// narrows the list. Category, account and status already show in the filter menu's own "On" state.
    @ViewBuilder
    private func activeFilterChips(filter: Binding<TransactionFilter>) -> some View {
        let amountLabel = amountRangeLabel(filter.wrappedValue)
        if let range = filter.wrappedValue.dateRange {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    removableChip(dateRangeLabel(range), identifier: "budget.chip.dateRange") {
                        filter.wrappedValue.dateRange = nil
                    }
                    if let amountLabel {
                        removableChip(amountLabel, identifier: "budget.chip.amountRange") {
                            filter.wrappedValue.minimumAmountMinorUnits = nil
                            filter.wrappedValue.maximumAmountMinorUnits = nil
                        }
                    }
                    clearAllChip(filter)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        } else if let amountLabel {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    removableChip(amountLabel, identifier: "budget.chip.amountRange") {
                        filter.wrappedValue.minimumAmountMinorUnits = nil
                        filter.wrappedValue.maximumAmountMinorUnits = nil
                    }
                    clearAllChip(filter)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    private func removableChip(_ text: String, identifier: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "xmark.circle.fill")
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Removes this filter")
        .accessibilityIdentifier(identifier)
    }

    private func clearAllChip(_ filter: Binding<TransactionFilter>) -> some View {
        Button("Clear All Filters", role: .destructive) { clearAllFilters(filter) }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityIdentifier("budget.clearAllFilters")
    }

    /// Resets every filter (category, uncategorized, date, amount, account, status) and the search text (Sprint 23
    /// hand check: "All time" only ever cleared the dates, leaving an amount filter active with nothing to undo it).
    private func clearAllFilters(_ filter: Binding<TransactionFilter>) {
        filter.wrappedValue = TransactionFilter()
        searchText = ""
        appliedSearch = ""
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
            // Near the top: the pickers below make the menu long enough that its end is off screen (CI run
            // 36388432939: Clear All Filters at the bottom could not be reached).
            Section {
                if hasAnyFilter(filter.wrappedValue) {
                    Button("Clear All Filters", systemImage: "xmark.circle", role: .destructive) {
                        clearAllFilters(filter)
                    }
                    .accessibilityIdentifier("budget.clearAllFilters.menu")
                }
                Button("More filters…", systemImage: "slider.horizontal.3") { isShowingMoreFilters = true }
                if hasAnyFilter(filter.wrappedValue) {
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
                Text("All time").tag(TransactionFilter.Period?.some(.all))
                Text("This week").tag(TransactionFilter.Period?.some(.thisWeek))
                Text("This month").tag(TransactionFilter.Period?.some(.thisMonth))
                Text("Last 30 days").tag(TransactionFilter.Period?.some(.last30Days))
                // Ticked only while a custom date range (More filters, or opened from Analytics) is active; picking
                // it again does nothing, since there is no preset behind it to switch to.
                if filter.wrappedValue.dateRange != nil {
                    Text("Custom").tag(TransactionFilter.Period?.none)
                }
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
