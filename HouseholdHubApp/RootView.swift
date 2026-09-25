import SwiftUI

enum AppInfo {
    static let displayName = "Household Hub"
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(AppInfo.displayName)
                .font(.title2)
                .bold()
                .accessibilityIdentifier("root.title")
        }
        .padding()
    }
}

#Preview {
    RootView()
}
