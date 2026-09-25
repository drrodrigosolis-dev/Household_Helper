import SwiftUI

/// Shown when the local store cannot be opened. Never deletes or recreates the store (spec Principle E, §5.3).
struct StoreUnavailableView: View {
    let error: any Error

    var body: some View {
        ContentUnavailableView {
            Label("Your data couldn't be opened", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        }
    }
}
