import Observation

/// Cross-tab navigation state so Dashboard cards can deep-link into the owning tab's filtered view (spec §24.2).
@MainActor
@Observable
final class AppRouter {
    /// One router for the app's single window, so App Intents (Shortcuts) can reach it.
    static let shared = AppRouter()

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
    /// Quick Add opened from outside the app (widget link, Shortcuts), shown over whatever tab is active.
    var isQuickAddPresented = false
    /// True while first-run setup is showing; outside requests to open Quick Add wait until it is done.
    var isOnboarding = false

    func showBudget(_ segment: BudgetView.Segment, filter: TransactionFilter = TransactionFilter()) {
        budgetSegment = segment
        budgetFilter = filter
        tab = .budget
    }
}
