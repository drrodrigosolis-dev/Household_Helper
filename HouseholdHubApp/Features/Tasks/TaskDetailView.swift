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
                if let rule = task.recurrence {
                    LabeledContent("Repeats", value: RecurrenceFormat.describe(rule))
                        .accessibilityIdentifier("task.repeats")
                }
                if let completed = task.completedAt {
                    LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                }
                if let wish = wishes.first(where: { $0.id == task.linkedWishlistItemID }) {
                    LabeledContent("Wishlist item", value: wish.name)
                }
                if let transactionID = task.linkedTransactionID {
                    LinkedTransactionRow(id: transactionID)
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
                // A plain menu (no long press, no drag) is the dependable non-drag path to another column (§24.5).
                // The label fills the row so a tap anywhere on it opens the menu, as for the buttons around it; the
                // default label is only as wide as its text (run 36209505191).
                Menu {
                    ForEach(columns.filter { $0.id != task.columnID }) { column in
                        Button(column.name) { move(task, to: column.id) }
                    }
                } label: {
                    Label("Move to…", systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("task.moveTo")
                Button("Archive", systemImage: "archivebox") { archive(task) }
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
            if let errorMessage {
                ErrorText(errorMessage)
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
        // Non-drag alternatives for reordering (spec §24.5) and a non-swipe delete.
        .contextMenu {
            subtaskMoves(subtask)
            Button("Delete", systemImage: "trash", role: .destructive) {
                let id = subtask.id
                run { try await $0.board.deleteSubtasks([id]) }
            }
        }
        .accessibilityActions { subtaskMoves(subtask) }
    }

    @ViewBuilder
    private func subtaskMoves(_ subtask: SubtaskItem) -> some View {
        if let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
            let id = subtask.id
            if index > 0 {
                Button("Move up", systemImage: "arrow.up") {
                    run { try await $0.board.moveSubtask(id, to: index - 1, now: .now) }
                }
            }
            if index < subtasks.count - 1 {
                Button("Move down", systemImage: "arrow.down") {
                    run { try await $0.board.moveSubtask(id, to: index + 1, now: .now) }
                }
            }
        }
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

    private func move(_ task: TaskItem, to columnID: UUID) {
        let id = task.id
        run { try await $0.board.moveTask(id, to: columnID, at: Int.max, now: .now) }
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
    /// The most recent transactions offered for linking, plus the linked one (fetched separately below).
    @Query private var recentTransactions: [TransactionRecord]
    @Query private var linkedTransactions: [TransactionRecord]

    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var wishID: UUID?
    @State private var transactionID: UUID?
    /// nil = doesn't repeat. `keptRule` is a stored rule the picker can't express, kept unless the user picks again.
    @State private var repeatChoice: TaskRepeat?
    @State private var keptRule: RecurrenceRule?
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(task: TaskItem?) {
        var recent = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        recent.fetchLimit = 50
        _recentTransactions = Query(recent)
        // A fresh UUID matches nothing when there is no link, keeping the predicate non-optional.
        let linked = task?.linkedTransactionID ?? UUID()
        _linkedTransactions = Query(filter: #Predicate<TransactionRecord> { $0.id == linked })
        _transactionID = State(initialValue: task?.linkedTransactionID)
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _priority = State(initialValue: task?.priority ?? .medium)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? .now)
        _wishID = State(initialValue: task?.linkedWishlistItemID)
        if let rule = task?.recurrence, let due = task?.dueDate {
            let calendar = HouseholdCalendar(timeZone: .current)
            let choice = TaskRepeat(rule: rule, dueDate: due, calendar: calendar)
            _repeatChoice = State(initialValue: choice)
            _keptRule = State(initialValue: choice == nil ? rule : nil)
        }
    }

    private var repeatBinding: Binding<TaskRepeat?> {
        Binding(
            get: { repeatChoice },
            set: { choice in
                repeatChoice = choice
                keptRule = nil
            })
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    private var linkableTransactions: [TransactionRecord] {
        let recent = recentTransactions
        return linkedTransactions.filter { linked in !recent.contains { $0.id == linked.id } } + recent
    }

    /// Open wishlist items, plus the currently linked one whatever its status.
    private var linkableWishes: [WishlistItem] {
        wishes.filter { $0.id == wishID || $0.status == .wanted || $0.status == .pending }
    }

    var body: some View {
        Form {
            Section {
                FocusingRow("Title") {
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
                    .accessibilityIdentifier("task.editor.hasDueDate")
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeat", selection: repeatBinding) {
                        if let keptRule {
                            Text(RecurrenceFormat.describe(keptRule)).tag(TaskRepeat?.none)
                        } else {
                            Text("Never").tag(TaskRepeat?.none)
                        }
                        ForEach(TaskRepeat.allCases, id: \.self) { choice in
                            Text(TaskRepeatFormat.title(choice)).tag(TaskRepeat?.some(choice))
                        }
                    }
                    .accessibilityIdentifier("task.editor.repeat")
                }
            } footer: {
                if hasDueDate, repeatChoice != nil || keptRule != nil {
                    Text("Completing it adds the next one, due on the next date after this due date.")
                }
            }
            Section {
                Picker("Wishlist item", selection: $wishID) {
                    Text("None").tag(UUID?.none)
                    ForEach(linkableWishes) { wish in
                        Text(wish.name).tag(UUID?.some(wish.id))
                    }
                }
                .accessibilityIdentifier("task.editor.wishlist")
                Picker("Transaction", selection: $transactionID) {
                    Text("None").tag(UUID?.none)
                    ForEach(linkableTransactions) { record in
                        Text(TaskEditorView.transactionTitle(record)).tag(UUID?.some(record.id))
                    }
                }
                .accessibilityIdentifier("task.editor.transaction")
                FocusingRow("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            }
            if let errorMessage {
                ErrorText(errorMessage)
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

    /// "Café Luna · Sep 21 · −CA$47.50": what it was, when, and how much.
    static func transactionTitle(_ record: TransactionRecord) -> String {
        let what = record.merchantNameSnapshot ?? record.notes ?? String(localized: "Transaction")
        let when = record.occurredAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(what) · \(when) · \(LedgerFormat.signedAmount(record.amount, type: record.type))"
    }

    private func save() async {
        guard let services, canSave else { return }
        isSaving = true
        defer { isSaving = false }
        // A due date is a calendar day (spec §10): stored as the start of that day in the household calendar.
        let calendar = HouseholdCalendar(timeZone: .current)
        let due = hasDueDate ? calendar.startOfDay(for: dueDate) : nil
        // A repeat needs a due date (Sprint 13): turning the due date off stops the repeat.
        let recurrence = due.flatMap { day in repeatChoice?.rule(dueDate: day, calendar: calendar) ?? keptRule }
        let draft = TaskDraft(
            title: title, notes: notes, priority: priority, dueDate: due, linkedWishlistItemID: wishID,
            linkedTransactionID: transactionID, recurrence: recurrence, timeZone: calendar.timeZone)
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

/// The task's linked transaction, fetched by id only.
private struct LinkedTransactionRow: View {
    @Query private var matches: [TransactionRecord]

    init(id: UUID) {
        _matches = Query(filter: #Predicate<TransactionRecord> { $0.id == id })
    }

    var body: some View {
        if let record = matches.first {
            LabeledContent("Transaction", value: TaskEditorView.transactionTitle(record))
                .accessibilityIdentifier("task.transaction")
        }
    }
}

/// Repeat choice titles (Sprint 13).
enum TaskRepeatFormat {
    static func title(_ choice: TaskRepeat) -> String {
        switch choice {
        case .daily: return String(localized: "Daily")
        case .weekly: return String(localized: "Weekly")
        case .everyTwoWeeks: return String(localized: "Every 2 weeks")
        case .monthly: return String(localized: "Monthly")
        case .yearly: return String(localized: "Yearly")
        }
    }
}
