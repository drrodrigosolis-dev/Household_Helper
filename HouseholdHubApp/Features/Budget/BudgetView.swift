import SwiftUI

struct BudgetView: View {
    var body: some View {
        NavigationStack {
            FeaturePlaceholder(title: "Budget", message: "No transactions yet", systemImage: "list.bullet.rectangle")
        }
    }
}

#Preview {
    BudgetView()
}
