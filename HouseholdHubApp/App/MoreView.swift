import SwiftUI

/// "More" tab: the less-frequent destinations from spec §24.1.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    AnalyticsView()
                } label: {
                    Label("Analytics", systemImage: "chart.pie")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("More")
        }
    }
}

#Preview {
    MoreView()
}
