import HouseholdHubCore
import SwiftData
import SwiftUI

/// Budget tab (spec §24.2): Transactions / Recurring segments; transactions filtered by period, category, status.
struct BudgetView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case transactions
        case recurring

        var id: String { rawValue }
    }

    @Environment(AppRouter.self) private var router
    @State private var isPresentingQuickAdd = false
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            Group {
                switch router.budgetSegment {
                case .transactions:
                    TransactionListView(filter: router.budgetFilter)
                        .refreshable { isPresentingQuickAdd = true }
                case .recurring:
                    RecurringListView()
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("View", selection: $router.budgetSegment) {
                    Text("Transactions").tag(Segment.transactions)
                    Text("Recurring").tag(Segment.recurring)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityIdentifier("budget.segment")
            }
            .navigationTitle("Budget")
            .toolbar {
                if router.budgetSegment == .transactions {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu(filter: $router.budgetFilter) }
                }
            }
            .sheet(isPresented: $isPresentingQuickAdd) { QuickAddView() }
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
        .accessibilityIdentifier("budget.filter")
    }
}

#Preview {
    BudgetView()
        .environment(AppRouter())
}
