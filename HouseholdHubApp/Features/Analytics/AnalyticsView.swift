import SwiftUI

/// Pushed inside the More tab's NavigationStack, so it must not create its own.
struct AnalyticsView: View {
    var body: some View {
        FeaturePlaceholder(title: "Analytics", message: "No data to analyze yet", systemImage: "chart.pie")
    }
}

#Preview {
    NavigationStack {
        AnalyticsView()
    }
}
