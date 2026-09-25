import SwiftUI

/// Tab structure is fixed by spec §24.1; each tab owns its NavigationStack.
struct AppRootView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "house") {
                DashboardView()
            }
            Tab("Budget", systemImage: "dollarsign.circle") {
                BudgetView()
            }
            Tab("Wishlist", systemImage: "heart") {
                WishlistView()
            }
            Tab("Tasks", systemImage: "checklist") {
                TasksView()
            }
            Tab("More", systemImage: "ellipsis") {
                MoreView()
            }
        }
    }
}

#Preview {
    AppRootView()
}
