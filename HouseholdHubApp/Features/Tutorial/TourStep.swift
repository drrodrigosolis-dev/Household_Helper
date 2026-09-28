import Foundation

/// Sprint 24: what a tour stop spotlights. A view marks itself with `.tourTarget(_:)`. Tab-bar items can't carry a
/// modifier, so a stop about a tab targets that screen's own content.
enum TourTarget: Hashable, Sendable {
    case figures
    case quickAdd
    case budgetList
    /// The first row of the transactions list: what "tap one to edit it" points at (owner's phone walk: a whole-screen
    /// spotlight pointed at nothing).
    case budgetRow
    /// Budget's "No transactions" message, when there is no row to point at yet.
    case budgetEmpty
    case wishlist
    /// The first wishlist item, where Mark Purchased is reached.
    case wishlistRow
    /// Wishlist's empty message and its Add item button.
    case wishlistEmpty
    case tasksBoard
    /// The first board column, where cards are dragged from.
    case tasksColumn
    case settings
}

/// The tab a stop shows; `TourController` opens it through `AppRouter`.
enum TourScreen: Hashable, Sendable {
    case dashboard
    case budget
    case wishlist
    case tasks
    case more
}

/// One stop of the first-run tour: a title and one or two short lines about the control it spotlights.
struct TourStep: Identifiable, Sendable {
    let target: TourTarget
    let screen: TourScreen
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var id: TourTarget { target }

    /// What the spotlight looks for, most specific first: a screen's first row or column when it has one, else its
    /// empty-state message, and the whole list only as a last resort (CI run 36442544785 showed whole-screen cut-outs).
    var targets: [TourTarget] {
        switch target {
        case .budgetList: [.budgetRow, .budgetEmpty, .budgetList]
        case .wishlist: [.wishlistRow, .wishlistEmpty, .wishlist]
        case .tasksBoard: [.tasksColumn, .tasksBoard]
        default: [target]
        }
    }

    /// The six stops the owner chose (Sprint 24): about a minute over the essentials. The first keeps the §9
    /// distinction: current, pending, and projected are three different figures, never all "balance".
    static let all: [TourStep] = [
        TourStep(
            target: .figures, screen: .dashboard, title: "Your money at a glance",
            message: "Current counts what's posted. Pending is still on its way, and Projected looks 30 days ahead."),
        TourStep(
            target: .quickAdd, screen: .dashboard, title: "Quick Add",
            message: "Tap + and type “12 coffee”. It's saved as an expense."),
        TourStep(
            target: .budgetList, screen: .budget, title: "Your transactions",
            message: "Tap one to edit it, swipe it for more, or tap Select to change several at once."),
        TourStep(
            target: .wishlist, screen: .wishlist, title: "Wishlist",
            message: "Bought something on your list? Tap Mark Purchased and the expense is recorded for you."),
        TourStep(
            target: .tasksBoard, screen: .tasks, title: "Tasks board",
            message: "Drag a card to another column as things move along, or touch and hold it and choose Move to…"),
        TourStep(
            target: .settings, screen: .more, title: "More › Settings",
            message: "Pick a theme here, and replay this tour whenever you like."),
    ]
}
