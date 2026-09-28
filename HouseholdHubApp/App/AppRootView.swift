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
    /// Set when the lock is on but the device has no passcode, so nothing can authenticate.
    @State private var passcodeOff = false
    /// Sprint 19: Settings › Appearance › Style. A device setting, so `@AppStorage` rather than `AppSettings`.
    @AppStorage(ThemeSettings.themeKey) private var storedTheme = FunTheme.off.rawValue
    @AppStorage(ThemeSettings.animationsKey) private var themeAnimations = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var funTheme: ThemeSpec? { FunTheme(storedValue: storedTheme).spec }
    /// A theme sets the accent; the custom accent applies with themes off.
    private var accent: Color? { funTheme?.accent ?? settings.first?.accentColor.map { Color($0) } }
    /// A theme's icon for a tab, or the standard one.
    private func tabSymbol(_ tab: ThemedTab, _ standard: String) -> String {
        funTheme?.tabSymbols[tab] ?? standard
    }

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
        .alert("The lock can't protect Household Hub", isPresented: $passcodeOff) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                """
                This device has no passcode, so Face ID and the passcode can't be asked for. Set a passcode in the \
                Settings app, or turn off the lock in More › Settings › Privacy.
                """
            )
        }
        // Dragging a form down puts the keyboard away, on every screen (audit A-004).
        .scrollDismissesKeyboard(.interactively)
        .preferredColorScheme(colorScheme)
        .tint(accent)
        .fontDesign(funTheme == nil ? nil : .rounded)
        .scrollContentBackground(funTheme == nil ? .automatic : .hidden)
        .environment(\.funTheme, funTheme)
        .environment(\.themeAnimates, funTheme != nil && themeAnimations && !reduceMotion)
        .onChange(of: storedTheme, initial: true) { ThemeAppearance.apply(funTheme) }
        .onChange(of: dynamicTypeSize) { ThemeAppearance.apply(funTheme) }
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
                Task {
                    await WidgetSync.refresh(services)
                    // Reminders follow the latest tasks and bills (Sprint 14).
                    await ReminderSync.refresh(services)
                }
            }
        }
    }

    private func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        // The device passcode was removed after the lock was turned on: nothing can authenticate, and the device
        // itself is unprotected. The app opens for this session only and says why; the setting stays on, so the
        // lock works again as soon as a passcode is set (it never switches itself off for good).
        let success: Bool
        if BiometricGate.isAvailable {
            isAuthenticating = true
            success = await BiometricGate.authenticate(reason: String(localized: "Unlock Household Hub"))
            isAuthenticating = false
        } else {
            success = true
            passcodeOff = true
        }
        unlockFailed = !success
        isUnlocked = success
        if success, pendingQuickAdd {
            pendingQuickAdd = false
            router.isQuickAddPresented = true
        }
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab("Dashboard", systemImage: tabSymbol(.dashboard, "house"), value: AppRouter.AppTab.dashboard) {
                DashboardView()
            }
            Tab("Budget", systemImage: "dollarsign.circle", value: AppRouter.AppTab.budget) {
                BudgetView()
            }
            Tab("Wishlist", systemImage: tabSymbol(.wishlist, "heart"), value: AppRouter.AppTab.wishlist) {
                WishlistView()
            }
            Tab("Tasks", systemImage: tabSymbol(.tasks, "checklist"), value: AppRouter.AppTab.tasks) {
                TasksView()
            }
            Tab("More", systemImage: "ellipsis", value: AppRouter.AppTab.more) {
                MoreView()
            }
        }
        .environment(router)
        .overlay { CelebrationOverlay() }
        .task { await bootstrap() }
        .sheet(isPresented: $router.isQuickAddPresented) { QuickAddView() }
        .onChange(of: needsOnboarding, initial: true) { router.isOnboarding = needsOnboarding }
        .sheet(isPresented: $needsOnboarding) {
            OnboardingView { needsOnboarding = false }
                .interactiveDismissDisabled()
        }
    }

    /// The tab binding; a tap on the selected tab is a reselect (audit A-012).
    private var tabSelection: Binding<AppRouter.AppTab> {
        Binding(
            get: { router.tab },
            set: { tab in
                if tab == router.tab {
                    router.reselect(tab)
                }
                router.tab = tab
            })
    }

    /// First launch: seed system categories, then ask for currency and starting balance until onboarding is done.
    private func bootstrap() async {
        guard let services else { return }
        let now = Date.now
        // New data is named in the device's language (Sprint 16); UI tests keep English names.
        let language =
            ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting)
            ? SeedLanguage.english : SeedLanguage.preferred(Locale.preferredLanguages)
        await services.transactions.setSeedLanguage(language)
        try? await services.categories.seedSystemCategoriesIfNeeded(now: now, language: language)
        try? await services.board.seedDefaultColumnsIfNeeded(now: now, language: language)
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
