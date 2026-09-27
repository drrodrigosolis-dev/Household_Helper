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

    @State private var isAddingSeveral = false
    @State private var isManagingColumns = false
    @State private var pendingDelete: TaskItem?
    @State private var errorMessage: String?
    /// Sprint 14: narrows every column to the tasks whose title, notes or subtasks match.
    @State private var searchText = ""
    /// Sprint 18: the column centered on the board. Follows swipes, and moves to a column a task is moved or
    /// dragged into.
    @State private var focusedColumn: UUID?
    /// Drop targets under a drag right now (a column, or a card), each mapped to its column. Kept as a set rather
    /// than one value because entering a card and leaving its column arrive in no fixed order.
    @State private var dropTargets: [UUID: UUID] = [:]
    @State private var springTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .themedScreen()
                .navigationDestination(for: UUID.self) { id in
                    TaskDetailView(taskID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Columns", systemImage: "rectangle.split.3x1") { isManagingColumns = true }
                            .accessibilityIdentifier("tasks.columns")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add several", systemImage: "text.badge.plus") { isAddingSeveral = true }
                            .accessibilityIdentifier("tasks.addSeveral")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add task", systemImage: "plus") { isAdding = true }
                            .accessibilityIdentifier("tasks.add")
                    }
                }
                .sheet(isPresented: $isAdding) {
                    NavigationStack { TaskEditorView(task: nil) }
                }
                .sheet(isPresented: $isAddingSeveral) {
                    NavigationStack { BatchAddView(kind: .tasks) }
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

    /// Each column is 2/3 of the board's width, centered, with its neighbors peeking in on both sides (Sprint 18).
    private var board: some View {
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width * 2 / 3).rounded()
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { column in
                        columnView(column)
                            .frame(width: columnWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (proxy.size.width - columnWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedColumn, anchor: .center)
        }
        .onChange(of: hoveredColumn) { _, column in springLoad(column) }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage {
                ErrorText(errorMessage).padding()
            }
        }
    }

    /// The column a drag is over, if any.
    private var hoveredColumn: UUID? { dropTargets.values.first }

    /// Spring-loading (Sprint 18): a drag that rests on a peeking column for 0.6 s centers it, so a task can travel
    /// across several columns in one drag. SwiftUI has no edge auto-scroll while dragging. The slide moves the next
    /// column under a finger that stays still, so the column a drop would land in is outlined (`columnView`).
    private func springLoad(_ column: UUID?) {
        springTask?.cancel()
        springTask = nil
        guard let column, column != focusedColumn else { return }
        springTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, hoveredColumn == column else { return }
            focus(column)
        }
    }

    private func focus(_ column: UUID) {
        withAnimation(reduceMotion ? nil : .snappy) { focusedColumn = column }
    }

    private func dropTargeted(_ targeted: Bool, key: UUID, column: UUID) {
        dropTargets[key] = targeted ? column : nil
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
        .overlay {
            if hoveredColumn == column.id {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, lineWidth: 3)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: column.id, at: cards.count)
        } isTargeted: { dropTargeted($0, key: column.id, column: column.id) }
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
        } isTargeted: { dropTargeted($0, key: task.id, column: column.id) }
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

    /// Returns whether the drop was handled. Uses the `isTargeted:` drop API (deprecated only from iOS 27.2) because
    /// the iOS 26 session API reports hovering only from iOS 27.
    private func drop(_ items: [String], into columnID: UUID, at index: Int) -> Bool {
        dropTargets = [:]
        guard let id = items.first.flatMap(UUID.init(uuidString:)), let task = tasks.first(where: { $0.id == id })
        else { return false }
        move(task, to: columnID, at: index)
        return true
    }

    /// A move into another column centers that column; a move within a column leaves the board where it is.
    private func move(_ task: TaskItem, to columnID: UUID, at index: Int) {
        let id = task.id
        if task.columnID != columnID { focus(columnID) }
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
