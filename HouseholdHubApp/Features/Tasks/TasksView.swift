import HouseholdHubCore
import SwiftData
import SwiftUI

/// Tasks tab (spec §24.2): a Kanban board of horizontally scrolling columns. Cards drag to reorder or move between
/// columns, and every drag has a non-drag alternative in the card's context menu and VoiceOver actions (§24.5).
struct TasksView: View {
    @Environment(\.services) private var services
    @Query(sort: \BoardColumn.sortOrder) private var columns: [BoardColumn]
    @Query(filter: #Predicate<TaskItem> { $0.archivedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query private var subtasks: [SubtaskItem]

    @State private var isAdding = false
    @State private var isManagingColumns = false
    @State private var pendingDelete: TaskItem?
    @State private var errorMessage: String?
    /// Sprint 14: narrows every column to the tasks whose title, notes or subtasks match.
    @State private var searchText = ""

    private var query: SearchQuery { SearchQuery(searchText) }

    private func matches(_ task: TaskItem, _ query: SearchQuery) -> Bool {
        guard !query.isEmpty else { return true }
        let steps = subtasks.filter { $0.taskID == task.id }.map { Optional($0.title) }
        return query.matches([task.title, task.notes] + steps)
    }

    var body: some View {
        NavigationStack {
            board
                .searchable(text: $searchText, prompt: "Search tasks")
                .quickAddAccess()
                .navigationTitle("Tasks")
                .navigationDestination(for: UUID.self) { id in
                    TaskDetailView(taskID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Columns", systemImage: "rectangle.split.3x1") { isManagingColumns = true }
                            .accessibilityIdentifier("tasks.columns")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add task", systemImage: "plus") { isAdding = true }
                            .accessibilityIdentifier("tasks.add")
                    }
                }
                .sheet(isPresented: $isAdding) {
                    NavigationStack { TaskEditorView(task: nil) }
                }
                .sheet(isPresented: $isManagingColumns) {
                    NavigationStack { ColumnsView() }
                }
                .confirmationDialog(
                    "Delete this task?", isPresented: deleteShown, titleVisibility: .visible, presenting: pendingDelete
                ) { task in
                    Button("Delete \(task.title)", role: .destructive) { delete(task) }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("The task and its subtasks will be removed.")
                }
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in
                    columnView(column)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.85 }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollTargetBehavior(.viewAligned)
        .safeAreaInset(edge: .bottom) {
            if let errorMessage {
                ErrorText(errorMessage).padding()
            }
        }
    }

    private func columnView(_ column: BoardColumn) -> some View {
        let query = query
        let cards = tasks.filter { $0.columnID == column.id && matches($0, query) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name).font(.headline)
                Spacer()
                Text("\(cards.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(cards.count) tasks")
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, task in
                        card(task, index: index, in: column, count: cards.count)
                    }
                    if cards.isEmpty {
                        Text("No tasks")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(.bottom, 96)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: column.id, at: cards.count)
        }
        .accessibilityIdentifier("tasks.column")
    }

    private func card(_ task: TaskItem, index: Int, in column: BoardColumn, count: Int) -> some View {
        NavigationLink(value: task.id) {
            TaskCard(task: task, subtasks: subtasks.filter { $0.taskID == task.id })
        }
        .buttonStyle(.plain)
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: column.id, at: index)
        }
        .contextMenu { menu(for: task, index: index, in: column, count: count) }
        .accessibilityActions { accessibilityMenu(for: task, index: index, in: column, count: count) }
    }

    /// The non-drag alternative (spec §24.5): the same actions in the context menu and as VoiceOver actions.
    @ViewBuilder
    private func menu(for task: TaskItem, index: Int, in column: BoardColumn, count: Int) -> some View {
        if task.completedAt == nil {
            Button("Mark complete", systemImage: "checkmark.circle") { setCompleted(true, task) }
        } else {
            Button("Reopen", systemImage: "arrow.uturn.backward.circle") { setCompleted(false, task) }
        }
        Menu("Move to…") {
            ForEach(columns.filter { $0.id != column.id }) { target in
                Button(target.name) { move(task, to: target.id, at: Int.max) }
            }
        }
        if index > 0 {
            Button("Move up", systemImage: "arrow.up") { move(task, to: column.id, at: index - 1) }
        }
        if index < count - 1 {
            Button("Move down", systemImage: "arrow.down") { move(task, to: column.id, at: index + 1) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = task }
    }

    /// VoiceOver actions are a flat list, so "Move to…" becomes one action per destination column.
    @ViewBuilder
    private func accessibilityMenu(for task: TaskItem, index: Int, in column: BoardColumn, count: Int) -> some View {
        if task.completedAt == nil {
            Button("Mark complete") { setCompleted(true, task) }
        } else {
            Button("Reopen") { setCompleted(false, task) }
        }
        ForEach(columns.filter { $0.id != column.id }) { target in
            Button("Move to \(target.name)") { move(task, to: target.id, at: Int.max) }
        }
        if index > 0 {
            Button("Move up") { move(task, to: column.id, at: index - 1) }
        }
        if index < count - 1 {
            Button("Move down") { move(task, to: column.id, at: index + 1) }
        }
        Button("Delete") { pendingDelete = task }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// Returns whether the drop was handled; the current `dropDestination` action ignores it, so it is discardable.
    @discardableResult
    private func drop(_ items: [String], into columnID: UUID, at index: Int) -> Bool {
        guard let id = items.first.flatMap(UUID.init(uuidString:)), let task = tasks.first(where: { $0.id == id })
        else { return false }
        move(task, to: columnID, at: index)
        return true
    }

    private func move(_ task: TaskItem, to columnID: UUID, at index: Int) {
        let id = task.id
        run { try await $0.board.moveTask(id, to: columnID, at: index, now: .now) }
    }

    private func setCompleted(_ completed: Bool, _ task: TaskItem) {
        let id = task.id
        run { try await $0.board.setTaskCompleted(completed, task: id, now: .now) }
    }

    private func delete(_ task: TaskItem) {
        let id = task.id
        pendingDelete = nil
        run { try await $0.board.deleteTask(id) }
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

/// One card: title, priority, due date, subtask progress. Read by VoiceOver as one element.
struct TaskCard: View {
    let task: TaskItem
    let subtasks: [SubtaskItem]

    private var done: Int { subtasks.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if task.completedAt != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Completed")
                }
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.completedAt != nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { details }
                VStack(alignment: .leading, spacing: 2) { details }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .systemBackground)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task.card")
    }

    @ViewBuilder
    private var details: some View {
        Text("\(WishlistFormat.priorityText(task.priority)) priority")
        if let due = task.dueDate {
            Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
        }
        if task.recurrenceRuleData != nil {
            Label("Repeats", systemImage: "repeat")
                .labelStyle(.iconOnly)
                .accessibilityLabel("Repeats")
        }
        if !subtasks.isEmpty {
            Label("\(done) of \(subtasks.count)", systemImage: "checklist")
        }
    }
}

#Preview {
    TasksView()
}
