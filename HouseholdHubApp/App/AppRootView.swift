import HouseholdHubCore
import SwiftUI

/// Tab structure is fixed by spec §24.1; each tab owns its NavigationStack.
struct AppRootView: View {
    @Environment(\.services) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var needsOnboarding = false
    @State private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Dashboard", systemImage: "house", value: AppRouter.AppTab.dashboard) {
                DashboardView()
            }
            Tab("Budget", systemImage: "dollarsign.circle", value: AppRouter.AppTab.budget) {
                BudgetView()
            }
            Tab("Wishlist", systemImage: "heart", value: AppRouter.AppTab.wishlist) {
                WishlistView()
            }
            Tab("Tasks", systemImage: "checklist", value: AppRouter.AppTab.tasks) {
                TasksView()
            }
            Tab("More", systemImage: "ellipsis", value: AppRouter.AppTab.more) {
                MoreView()
            }
        }
        .environment(router)
        .task { await bootstrap() }
        .sheet(isPresented: $router.isQuickAddPresented) { QuickAddView() }
        .onOpenURL { url in
            // The only link the app handles: the widget's Quick Add (spec §24.4). Not while onboarding.
            if url == WidgetSnapshot.quickAddURL, !needsOnboarding {
                router.isQuickAddPresented = true
            }
        }
        .onChange(of: scenePhase) {
            // Leaving the app is when the Home Screen becomes visible; refresh the widget's figures then.
            if scenePhase == .background {
                Task { await WidgetSync.refresh(services) }
            }
        }
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
        try? await services.board.seedDefaultColumnsIfNeeded(now: now)
        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.skipOnboarding) {
            try? await services.transactions.completeOnboarding(
                currencyCode: "CAD", startingBalance: .zero("CAD"), asOf: now, now: now)
        }
        let settings = try? await services.transactions.settingsSnapshot()
        needsOnboarding = settings?.onboardingCompleted != true
        await WidgetSync.refresh(services)
    }
}

#Preview {
    AppRootView()
}
