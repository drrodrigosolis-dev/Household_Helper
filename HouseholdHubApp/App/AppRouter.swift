import Observation

/// Cross-tab navigation state so Dashboard cards can deep-link into the owning tab's filtered view (spec §24.2).
@MainActor
@Observable
final class AppRouter {
    enum AppTab: Hashable {
        case dashboard
        case budget
        case wishlist
        case tasks
        case more
    }

    var tab = AppTab.dashboard
    var budgetSegment = BudgetView.Segment.transactions
    var budgetFilter = TransactionFilter()

    func showBudget(_ segment: BudgetView.Segment, filter: TransactionFilter = TransactionFilter()) {
        budgetSegment = segment
        budgetFilter = filter
        tab = .budget
    }
}
