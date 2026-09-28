import HouseholdHubCore
import SwiftUI

/// Saved bank presets (Sprint 23, F8), reachable from the CSV import preview's "Preset" picker. Swipe to delete one.
struct CSVImportPresetListView: View {
    let presetStore: CSVImportPresetStore
    @Binding var presets: [CSVImportPreset]

    var body: some View {
        List {
            if presets.isEmpty {
                Text("No saved presets yet. Map a file's columns, then choose “Save as preset…”.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presets) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                        Text(preset.headerSignature.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Import presets")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            presetStore.delete(id: presets[index].id)
        }
        presets.remove(atOffsets: offsets)
    }
}
