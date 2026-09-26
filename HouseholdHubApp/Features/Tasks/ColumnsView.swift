import HouseholdHubCore
import SwiftData
import SwiftUI

/// Column management (spec §7.10, §8.5): add, rename, reorder, and delete a custom column after choosing where its
/// tasks go. The last column is the "done" column (Sprint 4 default 2), which the footer says plainly.
struct ColumnsView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BoardColumn.sortOrder) private var columns: [BoardColumn]
    @Query(filter: #Predicate<TaskItem> { $0.archivedAt == nil }) private var tasks: [TaskItem]

    @State private var newName = ""
    @State private var renaming: BoardColumn?
    @State private var renameText = ""
    @State private var pendingDelete: BoardColumn?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(columns) { column in
                    row(column)
                }
                .onMove { source, destination in move(from: source, to: destination) }
            } footer: {
                Text("Tasks in the last column count as complete. Drag the handles to reorder.")
            }
            Section {
                HStack {
                    TextField("New column", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("columns.newName")
                    Button("Add column", systemImage: "plus.circle.fill", action: add)
                        .labelStyle(.iconOnly)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Columns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Rename column", isPresented: renameShown, presenting: renaming) { column in
            TextField("Name", text: $renameText)
            Button("Save") { rename(column) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this column?", isPresented: deleteShown, titleVisibility: .visible, presenting: pendingDelete
        ) { column in
            ForEach(columns.filter { $0.id != column.id }) { target in
                Button("Move tasks to \(target.name) and delete", role: .destructive) { delete(column, to: target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { column in
            Text(deleteMessage(column))
        }
    }

    private func row(_ column: BoardColumn) -> some View {
        HStack {
            Text(column.name)
            Spacer()
            Text("\(tasks.filter { $0.columnID == column.id }.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Menu {
                Button("Rename", systemImage: "pencil") {
                    renameText = column.name
                    renaming = column
                }
                if !column.isSystem {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = column }
                }
            } label: {
                Label("Actions for \(column.name)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
        }
        .accessibilityIdentifier("columns.row")
    }

    private func deleteMessage(_ column: BoardColumn) -> String {
        let count = tasks.filter { $0.columnID == column.id }.count
        if count == 0 {
            return String(localized: "Choose where tasks would go; this column is empty.")
        }
        return String(localized: "Its \(count) tasks move to the column you choose before it is deleted.")
    }

    private var renameShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newName = ""
        run { try await $0.board.createColumn(named: name, now: .now) }
    }

    private func rename(_ column: BoardColumn) {
        let id = column.id
        let name = renameText
        renaming = nil
        run { try await $0.board.renameColumn(id, to: name, now: .now) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let id = columns[from].id
        let index = destination > from ? destination - 1 : destination
        run { try await $0.board.moveColumn(id, to: index, now: .now) }
    }

    private func delete(_ column: BoardColumn, to target: BoardColumn) {
        let id = column.id
        let destination = target.id
        pendingDelete = nil
        run { try await $0.board.deleteColumn(id, movingTasksTo: destination, now: .now) }
    }

    private func run(_ action: @escaping @MainActor (AppServices) async throws -> Void) {
        guard let services else { return }
        Task {
            do {
                try await action(services)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "That change couldn't be saved.")
            }
        }
    }
}
