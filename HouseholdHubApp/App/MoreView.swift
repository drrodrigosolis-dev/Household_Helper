import SwiftUI

/// "More" tab: the less-frequent destinations from spec §24.1.
struct MoreView: View {
    enum Destination: Hashable {
        case analytics
        case settings
    }

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.morePath) {
            List {
                NavigationLink(value: Destination.analytics) {
                    Label("Analytics", systemImage: "chart.pie")
                }
                .themedRow()
                NavigationLink(value: Destination.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .themedRow()
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .analytics: AnalyticsView()
                case .settings: SettingsView()
                }
            }
            .quickAddAccess()
            .navigationTitle("More")
            .themedScreen(decorated: true)
        }
    }
}

#Preview {
    MoreView()
        .environment(AppRouter())
}
