import HouseholdHubCore
import SwiftUI

/// Tab structure is fixed by spec §24.1; each tab owns its NavigationStack.
struct AppRootView: View {
    @Environment(\.services) private var services
    @State private var needsOnboarding = false

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
        .task { await bootstrap() }
        .sheet(isPresented: $needsOnboarding) {
            OnboardingView { needsOnboarding = false }
                .interactiveDismissDisabled()
        }
    }

    /// First launch: seed system categories, then ask for currency and starting balance until onboarding is done.
    private func bootstrap() async {
        guard let services else { return }
        let now = Date.now
        try? await services.categories.seedSystemCategoriesIfNeeded(now: now)
        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.skipOnboarding) {
            try? await services.transactions.completeOnboarding(
                currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: now, now: now)
        }
        let settings = try? await services.transactions.settingsSnapshot()
        needsOnboarding = settings?.onboardingCompleted != true
    }
}

#Preview {
    AppRootView()
}
