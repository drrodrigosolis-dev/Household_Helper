import HouseholdHubCore
import SwiftData
import SwiftUI

/// Column management (spec §7.10, §8.5): add, rename, reorder, and delete a custom column after choosing where its
/// tasks go. The last column is the "done" column (Sprint 4 default 2), which the footer says plainly.
struct ColumnsView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BoardColumn.sortOrder) private var columns: [BoardColumn]
    /// All tasks, archived included: a column delete moves those too, so the dialog counts them.
    @Query private var tasks: [TaskItem]

    @State private var newName = ""
    @State private var renaming: BoardColumn?
    @State private var renameText = ""
    @State private var pendingDelete: BoardColumn?
    @State private var pendingReorder: Reorder?
    @State private var errorMessage: String?

    /// A reorder that changes which column is last, held for confirmation: it re-marks tasks complete or open.
    struct Reorder {
        let columnID: UUID
        let index: Int
        let newDone: String
        let oldDone: String
    }

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
        .alert("Change the done column?", isPresented: reorderShown, presenting: pendingReorder) { reorder in
            Button("Make \(reorder.newDone) the done column") { perform(reorder) }
            Button("Cancel", role: .cancel) {}
        } message: { reorder in
            Text("Tasks in \(reorder.newDone) will be marked complete and tasks in \(reorder.oldDone) reopened.")
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
            // Name first: at large text it wraps between words rather than being squeezed by the count and controls.
            VStack(alignment: .leading, spacing: 2) {
                Text(column.name)
                let count = tasks.filter { $0.columnID == column.id && $0.archivedAt == nil }.count
                Text("^[\(count) task](inflect: true)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
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
        let inColumn = tasks.filter { $0.columnID == column.id }
        let archived = inColumn.filter { $0.archivedAt != nil }.count
        if inColumn.isEmpty {
            return String(localized: "Choose where tasks would go; this column is empty.")
        }
        if archived > 0 {
            return String(
                localized: "Its \(inColumn.count) tasks (\(archived) archived) move to the column you choose first.")
        }
        return String(localized: "Its \(inColumn.count) tasks move to the column you choose before it is deleted.")
    }

    private var renameShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var reorderShown: Binding<Bool> {
        Binding(get: { pendingReorder != nil }, set: { if !$0 { pendingReorder = nil } })
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
        var order = columns
        let moved = order.remove(at: from)
        order.insert(moved, at: min(index, order.count))
        let reorder = Reorder(
            columnID: id, index: index, newDone: order.last?.name ?? "", oldDone: columns.last?.name ?? "")
        if order.last?.id != columns.last?.id {
            pendingReorder = reorder
        } else {
            perform(reorder)
        }
    }

    private func perform(_ reorder: Reorder) {
        pendingReorder = nil
        run { try await $0.board.moveColumn(reorder.columnID, to: reorder.index, now: .now) }
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
