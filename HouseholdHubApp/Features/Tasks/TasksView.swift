import HouseholdHubCore
import OSLog
import SwiftData
import SwiftUI

/// Debug-level, on-device only (never collected): what a drag did on the board, so a walk can read it with
/// `log stream --level debug --predicate 'category == "board"'` (L-030: the same gesture gave three outcomes).
private let boardLog = Logger(subsystem: "HouseholdHub", category: "board")

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
    /// Sprint 18: the column in focus, at the left edge of the board. Follows swipes, and moves to a column a task
    /// is moved or dragged into.
    /// Held as a `ScrollPosition` rather than a bare id so a column can be brought back to the edge even when its id
    /// is already the position's (L-029: the drag auto-scroll leaves the board between columns without changing it).
    @State private var position = ScrollPosition(idType: UUID.self)
    private var focusedColumn: UUID? { position.viewID(type: UUID.self) }
    /// Drop targets under a drag right now (a column, or a card), each mapped to its column. Kept as a set rather
    /// than one value because entering a card and leaving its column arrive in no fixed order.
    @State private var dropTargets: [UUID: UUID] = [:]
    /// Brings the board back onto a column's edge once a drag is over (see `settle`).
    @State private var settleTask: Task<Void, Never>?
    /// The column a drop asked the board to settle on; a later "drag over" signal keeps it rather than replacing it.
    @State private var settleColumn: UUID?
    /// The column the card being dragged started in; set when the drag begins, cleared by the drop (or by
    /// `settle` once nothing has been under the drag for a while: a drag released off every drop target).
    @State private var dragSource: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.funTheme) private var theme

    private var query: SearchQuery { SearchQuery(searchText) }

    private func matches(_ task: TaskItem, _ query: SearchQuery) -> Bool {
        guard !query.isEmpty else { return true }
        let steps = subtasks.filter { $0.taskID == task.id }.map { Optional($0.title) }
        return query.matches([task.title, task.notes] + steps)
    }

    var body: some View {
        NavigationStack {
            board
                .tourTarget(.tasksBoard)
                .searchable(text: $searchText, prompt: "Search tasks")
                .quickAddAccess()
                .navigationTitle("Tasks")
                .themedScreen(decorated: true, toolbarTrailing: true)
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

    /// Each column is 2/3 of the board's width, at the left edge, with the next one peeking in (Sprint 18).
    private var board: some View {
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width * 2 / 3).rounded()
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { column in
                        columnView(column)
                            .frame(width: columnWidth)
                            .tourTarget(.tasksColumn, if: column.id == columns.first?.id)
                    }
                }
                .scrollTargetLayout()
            }
            // Owner decision (Sprint 18 walk): columns line up with the left edge and the next one peeks in on the
            // right. The trailing margin lets the last column reach the left edge too.
            .contentMargins(.leading, Self.edge, for: .scrollContent)
            .contentMargins(.trailing, proxy.size.width - columnWidth - Self.edge, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position, anchor: .leading)
            // L-031/L-032 logs: whenever the board moved under a finger at rest (the system's drag auto-scroll, or a
            // spring-load), no drop came on release. So the board holds still for the whole drag: the next column
            // peeks in on the right and the previous one has the strip on the left, each a drop target, and a
            // drop moves the board to the card's new column. One column per drag (owner decision, L-018 to L-020).
            .scrollDisabled(dragSource != nil)
            .overlay(alignment: .leading) { previousColumnStrip }
        }
        .onChange(of: hoveredColumn) { _, column in
            let entry = "hover \(name(column)) focused \(name(focusedColumn))"
            boardLog.debug("\(entry, privacy: .public)")
            if column == nil { settle(on: nil) }
        }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage {
                ErrorText(errorMessage).padding()
            }
        }
    }

    /// Space before the column in focus.
    private static let edge: CGFloat = 16
    /// The drop strip along the left edge stands for the previous column, which no longer peeks in.
    private static let previousStripKey = UUID()

    /// The column before the one in focus, if any.
    private var previousColumn: UUID? {
        guard let index = columns.firstIndex(where: { $0.id == (focusedColumn ?? columns.first?.id) }), index > 0
        else { return nil }
        return columns[index - 1].id
    }

    /// With columns at the left edge the previous one is out of sight, so a drop on the left edge moves the task into
    /// it, as a drop on the peeking column on the right moves it into the next one.
    @ViewBuilder
    private var previousColumnStrip: some View {
        if let previous = previousColumn {
            // Only the margin before the column, so it never covers a card's tap area.
            Color.clear
                .frame(width: Self.edge)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    drop(items, into: previous, at: Int.max)
                } isTargeted: {
                    dropTargeted($0, key: Self.previousStripKey, column: previous)
                }
                .accessibilityHidden(true)
        }
    }

    /// The column a drag is over, if any.
    private var hoveredColumn: UUID? { dropTargets.values.first }

    /// The column a drop would land in now (see `drop`): outlined while dragging.
    private var dropColumn: UUID? {
        guard let hoveredColumn else { return nil }
        return oneColumnAway(from: dragSource ?? hoveredColumn, toward: hoveredColumn)
    }

    private func focus(_ column: UUID) {
        withAnimation(reduceMotion ? nil : .snappy) { position.scrollTo(id: column, anchor: .leading) }
    }

    /// The system's drag auto-scroll moves the board without view-aligned snapping, so a drag can leave it resting
    /// between columns (L-029: a sliver of To Do at the left, Done never in view), and a drop into the column already
    /// in focus didn't move it back, since the focused column's id was unchanged. Once the drag is over, the board
    /// goes back onto `column` (a drop's target) or the column in focus; `scrollTo` scrolls even to the same id.
    private func settle(on column: UUID?) {
        if let column { settleColumn = column }
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, hoveredColumn == nil,
                let target = settleColumn ?? dragSource ?? focusedColumn ?? columns.first?.id
            else { return }
            settleColumn = nil
            let entry = "settle on \(name(target)) from \(name(focusedColumn))"
            boardLog.debug("\(entry, privacy: .public)")
            focus(target)
            // Still over nothing a while later: the drag ended off every drop target, so the board scrolls again.
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled, hoveredColumn == nil else { return }
            dragSource = nil
        }
    }

    private func dropTargeted(_ targeted: Bool, key: UUID, column: UUID) {
        dropTargets[key] = targeted ? column : nil
    }

    private func columnView(_ column: BoardColumn) -> some View {
        let query = query
        let cards = tasks.filter { $0.columnID == column.id && matches($0, query) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.displayName(theme: theme)).themedFont(.headline)
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
                        Text(theme?.theme.emptyColumnText ?? String(localized: "No tasks"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(.bottom, 96)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .themedSurface(cornerRadius: 16, standard: Color(uiColor: .secondarySystemBackground))
        .overlay {
            if dropColumn == column.id {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, lineWidth: 3)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: column.id, at: cards.count)
        } isTargeted: {
            dropTargeted($0, key: column.id, column: column.id)
        }
        .accessibilityIdentifier("tasks.column")
    }

    private func card(_ task: TaskItem, index: Int, in column: BoardColumn, count: Int) -> some View {
        NavigationLink(value: task.id) {
            TaskCard(task: task, subtasks: subtasks.filter { $0.taskID == task.id })
        }
        .buttonStyle(.plain)
        .draggable(dragPayload(for: task))
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: column.id, at: index)
        } isTargeted: {
            dropTargeted($0, key: task.id, column: column.id)
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
                Button(target.displayName(theme: theme)) { move(task, to: target.id, at: Int.max) }
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
            Button("Move to \(target.displayName(theme: theme))") { move(task, to: target.id, at: Int.max) }
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
        dragSource = nil
        let target = oneColumnAway(from: task.columnID, toward: columnID)
        let entry = "drop over \(name(columnID)) from \(name(task.columnID)) to \(name(target))"
        boardLog.debug("\(entry, privacy: .public)")
        move(task, to: target, at: target == columnID ? index : Int.max)
        settle(on: target)
        return true
    }

    /// The drag's payload, evaluated as the drag begins; notes the column the card starts from.
    private func dragPayload(for task: TaskItem) -> String {
        let source = task.columnID
        Task { @MainActor in dragSource = source }
        return task.id.uuidString
    }

    /// A column's name for the board log.
    private func name(_ column: UUID?) -> String {
        column.flatMap { id in columns.first { $0.id == id }?.name } ?? "none"
    }

    /// One column per drag (owner decision, L-018 to L-020): the system's drag auto-scroll can carry the board past
    /// the next column before the drop (CI run 36511458730 and the L-029 hand walk: To Do straight to Done), so a
    /// drop further away lands in the next column that way, and the board settles there.
    private func oneColumnAway(from source: UUID, toward aimed: UUID) -> UUID {
        guard let from = columns.firstIndex(where: { $0.id == source }),
            let to = columns.firstIndex(where: { $0.id == aimed }), abs(to - from) > 1
        else { return aimed }
        return columns[from + (to > from ? 1 : -1)].id
    }

    /// A move into another column brings that column into focus; a move within a column leaves the board where it is.
    private func move(_ task: TaskItem, to columnID: UUID, at index: Int) {
        let id = task.id
        if task.columnID != columnID { focus(columnID) }
        // The last column is Done: moving an open task there completes it (Sprint 19 celebration).
        let completes = task.completedAt == nil && columnID == columns.last?.id
        run {
            try await $0.board.moveTask(id, to: columnID, at: index, now: .now)
            if completes { Celebration.shared.fire() }
        }
    }

    private func setCompleted(_ completed: Bool, _ task: TaskItem) {
        let id = task.id
        run {
            try await $0.board.setTaskCompleted(completed, task: id, now: .now)
            if completed { Celebration.shared.fire() }
        }
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
        .themedCard(cornerRadius: 12, standard: Color(uiColor: .systemBackground))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task.card")
    }

    @ViewBuilder
    private var details: some View {
        Text("\(WishlistFormat.priorityText(task.priority)) priority")
        if let due = task.dueDate {
            Label(TaskDueFormat.text(due: due, minutes: task.dueTimeMinutes), systemImage: "calendar")
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
