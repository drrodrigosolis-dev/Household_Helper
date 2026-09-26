import SwiftUI

/// Shown instead of the app while the Face ID gate is locked, and as the app-switcher cover.
struct LockView: View {
    let failed: Bool
    let isAuthenticating: Bool
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(AppInfo.displayName).font(.title2.weight(.semibold))
            if failed {
                Text("Household Hub is locked.").foregroundStyle(.secondary)
            }
            Button("Unlock with \(BiometricGate.methodName)", action: unlock)
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                .accessibilityIdentifier("lock.unlock")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    /// An opaque cover with no data on it.
    static var cover: some View {
        Image(systemName: "lock.fill")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .accessibilityHidden(true)
    }
}
