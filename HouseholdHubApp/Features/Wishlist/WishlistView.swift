import SwiftUI

struct WishlistView: View {
    var body: some View {
        NavigationStack {
            FeaturePlaceholder(title: "Wishlist", message: "No wishlist items yet", systemImage: "heart")
        }
    }
}

#Preview {
    WishlistView()
}
