import SwiftUI

struct TasksView: View {
    var body: some View {
        NavigationStack {
            FeaturePlaceholder(title: "Tasks", message: "No tasks yet", systemImage: "checklist")
                .quickAddAccess()
        }
    }
}

#Preview {
    TasksView()
}
