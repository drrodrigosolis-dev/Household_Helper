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

    @State private var segment = Segment.transactions
    @State private var filter = TransactionFilter()
    @State private var isPresentingQuickAdd = false
    @Query(sort: \CategoryRecord.sortOrder) private var categories: [CategoryRecord]

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .transactions:
                    TransactionListView(filter: filter)
                        .refreshable { isPresentingQuickAdd = true }
                case .recurring:
                    RecurringListView()
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("View", selection: $segment) {
                    Text("Transactions").tag(Segment.transactions)
                    Text("Recurring").tag(Segment.recurring)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityIdentifier("budget.segment")
            }
            .navigationTitle("Budget")
            .toolbar {
                if segment == .transactions {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu }
                }
            }
            .sheet(isPresented: $isPresentingQuickAdd) { QuickAddView() }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Period", selection: $filter.period) {
                Text("All time").tag(TransactionFilter.Period.all)
                Text("This week").tag(TransactionFilter.Period.thisWeek)
                Text("This month").tag(TransactionFilter.Period.thisMonth)
                Text("Last 30 days").tag(TransactionFilter.Period.last30Days)
            }
            Picker("Category", selection: $filter.categoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            Picker("Status", selection: $filter.status) {
                Text("Any status").tag(TransactionStatus?.none)
                ForEach(TransactionStatus.allCases, id: \.self) { status in
                    Text(LedgerFormat.statusLabel(status)).tag(TransactionStatus?.some(status))
                }
            }
            if filter.isActive {
                Button("Clear filters", role: .destructive) { filter = TransactionFilter() }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .symbolVariant(filter.isActive ? .fill : .none)
        }
        .accessibilityIdentifier("budget.filter")
    }
}

#Preview {
    BudgetView()
}
