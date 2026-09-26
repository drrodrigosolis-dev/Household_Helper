import HouseholdHubCore
import SwiftData
import SwiftUI

/// Task detail (spec §7.8, §7.9): facts, subtasks (add, check off, reorder, delete), complete/reopen, archive,
/// edit, and delete.
struct TaskDetailView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [TaskItem]
    @Query private var subtasks: [SubtaskItem]
    @Query(sort: \BoardColumn.sortOrder) private var columns: [BoardColumn]
    @Query private var wishes: [WishlistItem]

    @State private var newSubtask = ""
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(taskID: UUID) {
        _matches = Query(filter: #Predicate<TaskItem> { $0.id == taskID })
        _subtasks = Query(filter: #Predicate<SubtaskItem> { $0.taskID == taskID }, sort: \SubtaskItem.sortOrder)
    }

    var body: some View {
        Group {
            if let task = matches.first {
                details(task)
            } else {
                ContentUnavailableView("Task not found", systemImage: "checklist")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(_ task: TaskItem) -> some View {
        List {
            Section {
                LabeledContent("Column", value: columns.first { $0.id == task.columnID }?.name ?? "")
                    .accessibilityIdentifier("task.column")
                LabeledContent("Priority", value: WishlistFormat.priorityText(task.priority))
                if let due = task.dueDate {
                    LabeledContent("Due", value: due.formatted(date: .abbreviated, time: .omitted))
                }
                if let completed = task.completedAt {
                    LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                }
                if let wish = wishes.first(where: { $0.id == task.linkedWishlistItemID }) {
                    LabeledContent("Wishlist item", value: wish.name)
                }
                if let notes = task.notes {
                    Text(notes)
                }
            }
            Section("Subtasks") {
                ForEach(subtasks) { subtask in
                    subtaskRow(subtask)
                }
                .onMove { source, destination in moveSubtask(from: source, to: destination) }
                .onDelete { offsets in
                    let ids = offsets.map { subtasks[$0].id }
                    run { try await $0.board.deleteSubtasks(ids) }
                }
                HStack {
                    TextField("Add a subtask", text: $newSubtask)
                        .submitLabel(.done)
                        .onSubmit { addSubtask(to: task) }
                        .accessibilityIdentifier("task.newSubtask")
                    Button("Add", systemImage: "plus.circle.fill") { addSubtask(to: task) }
                        .labelStyle(.iconOnly)
                        .disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("task.addSubtask")
                }
            }
            Section {
                if task.completedAt == nil {
                    Button("Mark complete", systemImage: "checkmark.circle") { setCompleted(true, task) }
                        .accessibilityIdentifier("task.complete")
                } else {
                    Button("Reopen", systemImage: "arrow.uturn.backward.circle") { setCompleted(false, task) }
                }
                Button("Archive", systemImage: "archivebox") { archive(task) }
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(task.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { TaskEditorView(task: task) }
        }
        .confirmationDialog("Delete \(task.title)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete task", role: .destructive) { delete(task) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The task and its subtasks will be removed.")
        }
    }

    private func subtaskRow(_ subtask: SubtaskItem) -> some View {
        Button {
            let id = subtask.id
            let completed = !subtask.isCompleted
            run { try await $0.board.setSubtaskCompleted(completed, subtask: id, now: .now) }
        } label: {
            Label {
                Text(subtask.title).strikethrough(subtask.isCompleted)
            } icon: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
            }
        }
        .foregroundStyle(.primary)
        .accessibilityValue(subtask.isCompleted ? Text("Done") : Text("Not done"))
        .accessibilityIdentifier("task.subtask")
    }

    private func addSubtask(to task: TaskItem) {
        let title = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let id = task.id
        newSubtask = ""
        run { try await $0.board.addSubtask(titled: title, to: id, now: .now) }
    }

    private func moveSubtask(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let id = subtasks[from].id
        // `onMove` counts the destination before removal; the service expects the index after it.
        let index = destination > from ? destination - 1 : destination
        run { try await $0.board.moveSubtask(id, to: index, now: .now) }
    }

    private func setCompleted(_ completed: Bool, _ task: TaskItem) {
        let id = task.id
        run { try await $0.board.setTaskCompleted(completed, task: id, now: .now) }
    }

    private func archive(_ task: TaskItem) {
        let id = task.id
        run { services in
            try await services.board.setTaskArchived(true, task: id, now: .now)
            dismiss()
        }
    }

    private func delete(_ task: TaskItem) {
        let id = task.id
        run { services in
            try await services.board.deleteTask(id)
            dismiss()
        }
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

/// Create or edit a task (spec §7.8). New tasks go to the bottom of the first column.
struct TaskEditorView: View {
    let task: TaskItem?

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WishlistItem.name) private var wishes: [WishlistItem]

    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var wishID: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(task: TaskItem?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _priority = State(initialValue: task?.priority ?? .medium)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? .now)
        _wishID = State(initialValue: task?.linkedWishlistItemID)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    /// Open wishlist items, plus the currently linked one whatever its status.
    private var linkableWishes: [WishlistItem] {
        wishes.filter { $0.id == wishID || $0.status == .wanted || $0.status == .pending }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Title") {
                    TextField("Required", text: $title)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("task.editor.title")
                }
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases.reversed(), id: \.self) { value in
                        Text(WishlistFormat.priorityText(value)).tag(value)
                    }
                }
                Toggle("Due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                }
            }
            Section {
                Picker("Wishlist item", selection: $wishID) {
                    Text("None").tag(UUID?.none)
                    ForEach(linkableWishes) { wish in
                        Text(wish.name).tag(UUID?.some(wish.id))
                    }
                }
                LabeledContent("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(task == nil ? Text("New Task") : Text("Edit Task"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
                    .accessibilityIdentifier("task.editor.save")
            }
        }
    }

    private func save() async {
        guard let services, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        // A due date is a calendar day (spec §10): stored as the start of that day in the household calendar.
        let due = hasDueDate ? HouseholdCalendar(timeZone: .current).startOfDay(for: dueDate) : nil
        let draft = TaskDraft(
            title: title, notes: notes, priority: priority, dueDate: due, linkedWishlistItemID: wishID)
        do {
            if let task {
                try await services.board.updateTask(task.id, with: draft, now: .now)
            } else {
                try await services.board.createTask(draft, now: .now)
            }
            dismiss()
        } catch {
            errorMessage = String(localized: "This task couldn't be saved. Check the title.")
        }
    }
}
