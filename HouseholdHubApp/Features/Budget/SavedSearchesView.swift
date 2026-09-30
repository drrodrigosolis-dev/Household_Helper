import SwiftUI

/// Sprint 23 (F6): the saved searches, to delete ones no longer wanted. They are applied from the filter menu.
struct SavedSearchesView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var searches: [SavedSearch]

    var body: some View {
        Group {
            if searches.isEmpty {
                ContentUnavailableView {
                    Label("No saved searches", systemImage: "bookmark")
                } description: {
                    Text("Use Save search… in the filter menu to keep a search and its filters.")
                }
            } else {
                List {
                    ForEach(searches) { search in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(search.name)
                            if !search.text.isEmpty {
                                Text(search.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("savedSearches.row")
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Saved searches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            if !searches.isEmpty {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            SavedSearches.store.delete(id: searches[index].id)
        }
        searches = SavedSearches.store.all()
    }
}
