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
    /// When the last spring-load fired; one per drag (see `springLoad`). A drop clears it.
    @State private var springFiredAt: Date?
    @State private var springTask: Task<Void, Never>?
    /// The column the last spring-load brought into focus, held until the drop (or `springWindow`). While set, the
    /// board keeps that column in place: L-025 frames showed the system's drag auto-scroll carrying the board to its
    /// end ~0.3 s after a spring-load (the finger now rests in the edge band), so the drop landed past the columns.
    @State private var springColumn: UUID?
    /// Lets the board go `springWindow` after a spring-load if the drag ended off the board (no drop to clear it).
    @State private var springRelease: Task<Void, Never>?
    /// Brings the board back onto a column's edge once a drag is over (see `settle`).
    @State private var settleTask: Task<Void, Never>?
    /// The column a drop asked the board to settle on; a later "drag over" signal keeps it rather than replacing it.
    @State private var settleColumn: UUID?
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
            .overlay(alignment: .leading) { previousColumnStrip }
        }
        .onChange(of: hoveredColumn) { _, column in
            let entry = "hover \(name(column)) focused \(name(focusedColumn))"
            boardLog.debug("\(entry, privacy: .public)")
            springLoad(column)
            if column == nil, springColumn == nil { settle(on: nil) }
        }
        // Anything else that moves the board while a spring-load holds it (the drag auto-scroll) is undone. Scrolling
        // isn't disabled instead: that also stopped the spring-load's own scroll (CI run 36453971771).
        .onChange(of: focusedColumn) { _, column in
            if let springColumn, column != springColumn { focus(springColumn) }
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

    /// With columns at the left edge the previous one is out of sight, so a drag resting on the left edge slides
    /// back to it (spring-loading, like the peeking column on the right), and a drop there moves the task into it.
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
        return springColumn ?? (springSpent ? (focusedColumn ?? hoveredColumn) : hoveredColumn)
    }

    /// This drag has used its spring-load. A drag dropped off the board never reaches `drop`, so a spring-load more
    /// than `springWindow` ago counts as a previous drag's.
    private var springSpent: Bool {
        springFiredAt.map { Date.now.timeIntervalSince($0) < Self.springWindow } ?? false
    }

    private static let springWindow: TimeInterval = 8

    /// Spring-loading (Sprint 18): a drag that rests on a peeking column (or the left edge, for the previous one) for
    /// 0.6 s brings it into focus. SwiftUI has no edge auto-scroll while dragging. The slide moves the next column
    /// under a finger that stays still, so the column a drop would land in is outlined (`columnView`).
    ///
    /// One per drag (L-018, L-019, L-020 walks: a finger resting at the edge went two columns). Re-arming on what the
    /// drag was over failed twice: while a finger rests, the columns sliding under it report hover changes in no
    /// reliable order, both "over the focused column" and "over nothing". So nothing about hovering re-arms it; a drop
    /// does, and a drag that ended off the board is forgotten after `springWindow`. To go further, drop and drag again.
    private func springLoad(_ column: UUID?) {
        springTask?.cancel()
        springTask = nil
        guard let column, column != focusedColumn, !springSpent else { return }
        springTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, hoveredColumn == column, !springSpent else { return }
            let fired = Date.now
            springFiredAt = fired
            springColumn = column
            let entry = "spring-load to \(name(column))"
            boardLog.debug("\(entry, privacy: .public)")
            springRelease?.cancel()
            springRelease = Task {
                try? await Task.sleep(for: .seconds(Self.springWindow))
                guard !Task.isCancelled, springFiredAt == fired else { return }
                springColumn = nil
            }
            // The targets are stale once the board slides; the ones still under the drag report in again as it moves.
            dropTargets = [:]
            focus(column)
        }
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
            guard !Task.isCancelled, hoveredColumn == nil, springColumn == nil,
                let target = settleColumn ?? focusedColumn ?? columns.first?.id
            else { return }
            settleColumn = nil
            let entry = "settle on \(name(target)) from \(name(focusedColumn))"
            boardLog.debug("\(entry, privacy: .public)")
            focus(target)
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
        .draggable(task.id.uuidString)
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
    ///
    /// Right after a spring-load the finger is over a column that slid in under it; the drop goes to the column that
    /// sprang into focus, as the outline showed (L-018: a rest-then-drop on the right edge landed a column too far).
    private func drop(_ items: [String], into columnID: UUID, at index: Int) -> Bool {
        let aimed = springColumn ?? (springSpent ? (focusedColumn ?? columnID) : columnID)
        springColumn = nil
        springRelease?.cancel()
        dropTargets = [:]
        springFiredAt = nil
        guard let id = items.first.flatMap(UUID.init(uuidString:)), let task = tasks.first(where: { $0.id == id })
        else { return false }
        let target = oneColumnAway(from: task.columnID, toward: aimed)
        let entry = "drop over \(name(columnID)) aimed \(name(aimed)) from \(name(task.columnID)) to \(name(target))"
        boardLog.debug("\(entry, privacy: .public)")
        move(task, to: target, at: target == columnID ? index : Int.max)
        settle(on: target)
        return true
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
