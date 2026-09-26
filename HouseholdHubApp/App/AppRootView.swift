import HouseholdHubCore
import SwiftData
import SwiftUI

/// Tab structure is fixed by spec §24.1; each tab owns its NavigationStack.
struct AppRootView: View {
    @Environment(\.services) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]
    @State private var needsOnboarding = false
    @State private var router = AppRouter.shared
    /// Face ID gate state. The app starts locked when the gate is on; leaving it locks it again.
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var unlockFailed = false
    @State private var pendingQuickAdd = false

    private var lockEnabled: Bool { settings.first?.faceIDEnabled == true }

    /// The UI-test walk forces dark; otherwise Settings › Appearance decides, nil following the system.
    private var colorScheme: ColorScheme? {
        if ProcessInfo.processInfo.arguments.contains(LaunchArguments.darkMode) {
            return .dark
        }
        switch settings.first?.selectedTheme ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var accent: Color? { settings.first?.accentColor.map { Color($0) } }
    private var isLocked: Bool { lockEnabled && !isUnlocked }

    var body: some View {
        Group {
            // While locked nothing of the app is in the hierarchy, sheets included, so no figure can show.
            if isLocked {
                LockView(failed: unlockFailed, isAuthenticating: isAuthenticating) { Task { await unlock() } }
                    .task(id: scenePhase) {
                        if scenePhase == .active, !unlockFailed {
                            await unlock()
                        }
                    }
            } else {
                tabs
            }
        }
        .onOpenURL { url in
            // The only link the app handles: the widget's Quick Add (spec §24.4). Not while onboarding; after
            // unlocking when the gate is on.
            guard url == WidgetSnapshot.quickAddURL, !needsOnboarding else { return }
            if isLocked {
                pendingQuickAdd = true
            } else {
                router.isQuickAddPresented = true
            }
        }
        .preferredColorScheme(colorScheme)
        .tint(accent)
        // App switcher: cover the screen whenever the gated app isn't frontmost.
        .overlay {
            if lockEnabled, scenePhase != .active, !isAuthenticating {
                LockView.cover
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                isUnlocked = false
                unlockFailed = false
                // Leaving the app is when the Home Screen becomes visible; refresh the widget's figures then.
                Task { await WidgetSync.refresh(services) }
            }
        }
    }

    private func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        // The device passcode was removed after the lock was turned on: nothing can authenticate, and the device
        // itself is unprotected, so the gate turns itself off rather than lock the owner out of their data.
        guard BiometricGate.isAvailable else {
            try? await services?.transactions.setFaceIDEnabled(false, now: .now)
            isUnlocked = true
            return
        }
        isAuthenticating = true
        let reason = String(localized: "Unlock Household Hub")
        let success = await BiometricGate.authenticate(reason: reason)
        isAuthenticating = false
        unlockFailed = !success
        isUnlocked = success
        if success, pendingQuickAdd {
            pendingQuickAdd = false
            router.isQuickAddPresented = true
        }
    }

    private var tabs: some View {
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
        .onChange(of: needsOnboarding, initial: true) { router.isOnboarding = needsOnboarding }
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
