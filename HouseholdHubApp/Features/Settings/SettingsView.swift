import SwiftUI

/// Pushed inside the More tab's NavigationStack, so it must not create its own.
struct SettingsView: View {
    var body: some View {
        FeaturePlaceholder(title: "Settings", message: "Settings are coming soon", systemImage: "gearshape")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
