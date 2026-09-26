import SwiftUI

/// Empty-state screen used until a feature's real content lands in its phase.
struct FeaturePlaceholder: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        ContentUnavailableView(message, systemImage: systemImage)
            .navigationTitle(title)
    }
}
