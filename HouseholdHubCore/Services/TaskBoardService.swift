import Foundation
import SwiftData
import Synchronization

/// The Kanban board (spec §7.8–§7.10, §8.5): columns, tasks, subtasks, ordering, and the completion rule.
/// One instance per container, like the other services, so every board write goes through one serial context.
/// (`TransactionService` also clears task links when it deletes a wishlist item; see `existingWishlistLink`.)
///
/// Completion follows the board: the last column is the "done" column. A task in it has `completedAt`; a task
/// anywhere else does not. Every write that can change a task's column, or which column is last, re-applies this.
@ModelActor
public actor TaskBoardService {
    private static let instances = Mutex<[ObjectIdentifier: TaskBoardService]>([:])

    public static func make(container: ModelContainer) -> TaskBoardService {
        instances.withLock { cache in
            if let existing = cache[ObjectIdentifier(container)] {
                return existing
            }
            let service = TaskBoardService(modelContainer: container)
            cache[ObjectIdentifier(container)] = service
            return service
        }
    }

    public static let defaultColumnNames = ["To Do", "In Progress", "Done"]

    // MARK: Columns

    /// Inserts the default system columns once. Names are stored data and can be renamed.
    public func seedDefaultColumnsIfNeeded(now: Date) throws {
        begin()
        guard try modelContext.fetchCount(FetchDescriptor<BoardColumn>()) == 0 else { return }
        for (index, name) in Self.defaultColumnNames.enumerated() {
            modelContext.insert(BoardColumn(name: name, sortOrder: index, isSystem: true, now: now))
        }
        try commit()
    }

    /// Adds a custom column just before the done column, so "last column = done" keeps its meaning.
    @discardableResult
    public func createColumn(named name: String, now: Date) throws -> UUID {
        begin()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskBoardError.emptyColumnName }
        var ordered = try columns()
        let column = BoardColumn(name: trimmed, sortOrder: ordered.count, now: now)
        modelContext.insert(column)
        ordered.insert(column, at: max(ordered.count - 1, 0))
        renumber(ordered, now: now)
        try commit()
        return column.id
    }

    public func renameColumn(_ id: UUID, to name: String, now: Date) throws {
        begin()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskBoardError.emptyColumnName }
        let column = try requireColumn(id)
        column.name = trimmed
        column.updatedAt = now
        try commit()
    }

    /// Moves a column to `index` in the board order. If the done column changes, completion is re-applied.
    public func moveColumn(_ id: UUID, to index: Int, now: Date) throws {
        begin()
        var ordered = try columns()
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { throw TaskBoardError.unknownColumn }
        let column = ordered.remove(at: from)
        ordered.insert(column, at: min(max(index, 0), ordered.count))
        renumber(ordered, now: now)
        try applyCompletionRule(ordered, now: now)
        try commit()
    }

    /// Spec §8.5: a column with tasks is deleted only after its tasks move to `destination`, in the same save.
    public func deleteColumn(_ id: UUID, movingTasksTo destination: UUID, now: Date) throws {
        begin()
        let column = try requireColumn(id)
        guard !column.isSystem else { throw TaskBoardError.systemColumnIsPermanent }
        guard destination != id else { throw TaskBoardError.destinationIsSource }
        _ = try requireColumn(destination)
        var key = try tasks(in: destination, includingArchived: true).last?.sortOrder ?? 0
        for task in try tasks(in: id, includingArchived: true) {
            key += 1
            task.columnID = destination
            task.sortOrder = key
            task.updatedAt = now
        }
        modelContext.delete(column)
        let remaining = try columns().filter { $0.id != id }
        renumber(remaining, now: now)
        try applyCompletionRule(remaining, now: now)
        try commit()
    }

    // MARK: Tasks

    /// Adds a task at the bottom of `columnID`, or of the first column when nil.
    @discardableResult
    public func createTask(_ draft: TaskDraft, in columnID: UUID? = nil, now: Date) throws -> UUID {
        begin()
        try draft.validate()
        var draft = draft
        draft.linkedWishlistItemID = try existingWishlistLink(draft.linkedWishlistItemID)
        draft.linkedTransactionID = try existingTransactionLink(draft.linkedTransactionID)
        let ordered = try columns()
        let wanted = columnID.map { id in ordered.first { $0.id == id } } ?? ordered.first
        guard let column = wanted else { throw TaskBoardError.unknownColumn }
        // Keys come after archived tasks too, so an unarchived task never ties with a new one.
        let key = SortKey.between(try tasks(in: column.id, includingArchived: true).last?.sortOrder, nil) ?? 1
        let task = TaskItem(
            title: draft.trimmedTitle, columnID: column.id, priority: draft.priority, sortOrder: key, now: now)
        try apply(draft, to: task)
        modelContext.insert(task)
        try settleCompletion(of: task, columns: ordered, returnTo: nil, now: now)
        try linkBack(draft.linkedWishlistItemID, to: task.id, now: now)
        try commit()
        return task.id
    }

    public func updateTask(_ id: UUID, with draft: TaskDraft, now: Date) throws {
        begin()
        try draft.validate()
        var draft = draft
        draft.linkedWishlistItemID = try existingWishlistLink(draft.linkedWishlistItemID)
        draft.linkedTransactionID = try existingTransactionLink(draft.linkedTransactionID)
        let task = try requireTask(id)
        // A completed task may keep the rule it has (one completed by a column change), never gain a new one.
        guard draft.recurrence == nil || task.completedAt == nil || draft.recurrence == task.recurrence else {
            throw TaskBoardError.repeatOnCompletedTask
        }
        // A wishlist item that pointed back at this task keeps that link only if the task still points at it;
        // otherwise the pair would be one-sided and backups would refuse to validate.
        let target: UUID? = id
        let backLinked = try modelContext.fetch(
            FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.linkedTaskID == target }))
        for wish in backLinked where wish.id != draft.linkedWishlistItemID {
            wish.linkedTaskID = nil
            wish.updatedAt = now
        }
        task.title = draft.trimmedTitle
        task.priority = draft.priority
        try apply(draft, to: task)
        task.updatedAt = now
        try linkBack(draft.linkedWishlistItemID, to: id, now: now)
        try commit()
    }

    /// Moves a task to position `index` of `columnID` (0 = top), among the column's other visible tasks.
    public func moveTask(_ id: UUID, to columnID: UUID, at index: Int, now: Date) throws {
        begin()
        let task = try requireTask(id)
        _ = try requireColumn(columnID)
        let previousColumnID = task.columnID
        let siblings = try tasks(in: columnID).filter { $0.id != id }
        let position = min(max(index, 0), siblings.count)
        var key = SortKey.between(
            position > 0 ? siblings[position - 1].sortOrder : nil,
            position < siblings.count ? siblings[position].sortOrder : nil)
        if key == nil {
            // Neighbours too close to split: renumber the column 1, 2, 3, … and take the now-roomy midpoint.
            for (offset, sibling) in siblings.enumerated() {
                sibling.sortOrder = Double(offset + 1)
            }
            key = SortKey.between(Double(position), Double(position + 1))
        }
        task.columnID = columnID
        task.sortOrder = key ?? Double(position + 1)
        task.updatedAt = now
        try settleCompletion(of: task, columns: try columns(), returnTo: previousColumnID, now: now)
        try commit()
    }

    /// Completing moves the task to the bottom of the done column; reopening moves it to the bottom of the first.
    public func setTaskCompleted(_ completed: Bool, task id: UUID, now: Date) throws {
        begin()
        let ordered = try columns()
        guard let target = completed ? ordered.last : ordered.first else { throw TaskBoardError.unknownColumn }
        let task = try requireTask(id)
        guard (task.completedAt != nil) != completed else { return }
        let count = try tasks(in: target.id).filter { $0.id != id }.count
        try moveTask(id, to: target.id, at: count, now: now)
    }

    public func setTaskArchived(_ archived: Bool, task id: UUID, now: Date) throws {
        begin()
        let task = try requireTask(id)
        if !archived, task.archivedAt != nil {
            // Back at the bottom of its column with a fresh key; its old key may now tie with another task.
            let last = try tasks(in: task.columnID).last?.sortOrder
            task.sortOrder = SortKey.between(last, nil) ?? 1
            try settleCompletion(of: task, columns: try columns(), returnTo: nil, now: now)
        }
        task.archivedAt = archived ? now : nil
        task.updatedAt = now
        try commit()
    }

    /// Deletes the task and its subtasks in one save. Tasks are not financial history (spec §8 covers money only).
    public func deleteTask(_ id: UUID) throws {
        begin()
        let task = try requireTask(id)
        let children = try subtasks(of: id)
        // A wishlist item linked to this task loses the link rather than keep a dangling id (backups validate it).
        let target: UUID? = id
        let linkedWishes = try modelContext.fetch(
            FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.linkedTaskID == target }))
        for subtask in children {
            modelContext.delete(subtask)
        }
        for wish in linkedWishes {
            wish.linkedTaskID = nil
            wish.updatedAt = .now
        }
        modelContext.delete(task)
        try commit()
    }

    // MARK: Subtasks

    @discardableResult
    public func addSubtask(titled title: String, to taskID: UUID, now: Date) throws -> UUID {
        begin()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskBoardError.emptyTitle }
        let task = try requireTask(taskID)
        let key = SortKey.between(try subtasks(of: taskID).last?.sortOrder, nil) ?? 1
        let subtask = SubtaskItem(title: trimmed, taskID: taskID, sortOrder: key, now: now)
        modelContext.insert(subtask)
        task.updatedAt = now
        try commit()
        return subtask.id
    }

    public func setSubtaskCompleted(_ completed: Bool, subtask id: UUID, now: Date) throws {
        begin()
        let subtask = try requireSubtask(id)
        subtask.isCompleted = completed
        subtask.updatedAt = now
        try commit()
    }

    public func renameSubtask(_ id: UUID, to title: String, now: Date) throws {
        begin()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskBoardError.emptyTitle }
        let subtask = try requireSubtask(id)
        subtask.title = trimmed
        subtask.updatedAt = now
        try commit()
    }

    /// Moves a subtask to `index` within its task; subtask lists are short, so they are simply renumbered.
    public func moveSubtask(_ id: UUID, to index: Int, now: Date) throws {
        begin()
        let subtask = try requireSubtask(id)
        var ordered = try subtasks(of: subtask.taskID).filter { $0.id != id }
        ordered.insert(subtask, at: min(max(index, 0), ordered.count))
        for (offset, item) in ordered.enumerated() where item.sortOrder != Double(offset + 1) {
            item.sortOrder = Double(offset + 1)
            item.updatedAt = now
        }
        try commit()
    }

    /// Deletes several subtasks in one save, so a multi-row delete is all or nothing.
    public func deleteSubtasks(_ ids: [UUID]) throws {
        begin()
        for id in ids {
            modelContext.delete(try requireSubtask(id))
        }
        try commit()
    }

    public func deleteSubtask(_ id: UUID) throws {
        try deleteSubtasks([id])
    }

    // MARK: Helpers

    private func apply(_ draft: TaskDraft, to task: TaskItem) throws {
        let notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes?.isEmpty == false ? notes : nil
        task.dueDate = draft.dueDate
        task.linkedWishlistItemID = draft.linkedWishlistItemID
        task.linkedTransactionID = draft.linkedTransactionID
        task.recurrenceRuleData = try draft.recurrence?.encoded()
        task.recurrenceTimeZoneIdentifier = draft.recurrence == nil ? nil : draft.timeZone.identifier
    }

    private func renumber(_ ordered: [BoardColumn], now: Date) {
        for (index, column) in ordered.enumerated() where column.sortOrder != index {
            column.sortOrder = index
            column.updatedAt = now
        }
    }

    /// Sets or clears `completedAt` from the task's column (the last column is done). A repeating task that has just
    /// been completed hands its repeat to the next task (Sprint 13).
    /// - Parameters:
    ///   - returnTo: where the task was before this change; the next task goes there unless that is the done column,
    ///     else to the first column.
    ///   - repeats: false for board-wide changes (reordering or deleting columns): owner decision 21 says only a task
    ///     completed on its own adds its next one. Such a task keeps its rule, so reopening it leaves one series.
    private func settleCompletion(
        of task: TaskItem, columns ordered: [BoardColumn], returnTo: UUID?, repeats: Bool = true, now: Date
    ) throws {
        let isDone = task.columnID == ordered.last?.id
        if isDone, task.completedAt == nil {
            task.completedAt = now
            if repeats {
                try scheduleNext(after: task, columns: ordered, returnTo: returnTo, now: now)
            }
        } else if !isDone, task.completedAt != nil {
            task.completedAt = nil
        }
    }

    /// Archived tasks keep their completion history; only tasks on the board follow the done column.
    private func applyCompletionRule(_ ordered: [BoardColumn], now: Date) throws {
        let onBoard = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.archivedAt == nil })
        for task in try modelContext.fetch(onBoard) {
            try settleCompletion(of: task, columns: ordered, returnTo: nil, repeats: false, now: now)
        }
    }

    /// Sprint 13 decisions 2–4: a copy of the completed task (title, notes, priority, subtasks unticked; no links) due
    /// on the rule's next date after the completed task's due date, which keeps no rule, so completing it again or
    /// reopening it never makes a second copy. If no copy can be made (an unreadable rule, no next date, no open
    /// column) the rule stays where it is rather than being dropped; an unknown zone falls back to the device's.
    private func scheduleNext(
        after task: TaskItem, columns ordered: [BoardColumn], returnTo: UUID?, now: Date
    ) throws {
        guard let data = task.recurrenceRuleData, let rule = try? RecurrenceRule.decoded(from: data),
            let due = task.dueDate
        else { return }
        let zone = task.recurrenceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let open = ordered.dropLast()
        guard
            let next = RecurrenceEngine().nextOccurrence(
                of: rule, start: due, after: due, calendar: HouseholdCalendar(timeZone: zone)),
            let column = open.first(where: { $0.id == returnTo }) ?? open.first
        else { return }
        task.recurrenceRuleData = nil
        task.recurrenceTimeZoneIdentifier = nil
        let key = SortKey.between(try tasks(in: column.id, includingArchived: true).last?.sortOrder, nil) ?? 1
        let copy = TaskItem(title: task.title, columnID: column.id, priority: task.priority, sortOrder: key, now: now)
        copy.notes = task.notes
        copy.dueDate = next
        copy.recurrenceRuleData = data
        copy.recurrenceTimeZoneIdentifier = zone.identifier
        modelContext.insert(copy)
        for step in try subtasks(of: task.id) {
            modelContext.insert(SubtaskItem(title: step.title, taskID: copy.id, sortOrder: step.sortOrder, now: now))
        }
    }

    /// A link is optional metadata: one to an item deleted meanwhile (e.g. from another screen while an editor was
    /// open) is dropped rather than blocking the save.
    private func existingTransactionLink(_ id: UUID?) throws -> UUID? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<TransactionRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetchCount(descriptor) > 0 ? id : nil
    }

    /// Links are two-way (spec §7.7 `linkedTaskID`, §7.8 `linkedWishlistItemID`): the wishlist item points at the
    /// task that most recently linked it. Several tasks may link one item; the pair stays consistent for backups.
    private func linkBack(_ wishID: UUID?, to taskID: UUID, now: Date) throws {
        guard let wishID else { return }
        let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == wishID })
        guard let wish = try modelContext.fetch(descriptor).first, wish.linkedTaskID != taskID else { return }
        wish.linkedTaskID = taskID
        wish.updatedAt = now
    }

    private func existingWishlistLink(_ id: UUID?) throws -> UUID? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetchCount(descriptor) > 0 ? id : nil
    }

    /// Every write starts from a clean context: edits left behind by an operation that threw before reaching
    /// `commit()` (a failed fetch mid-way) are discarded here, so no later save can persist half an operation.
    private func begin() {
        if modelContext.hasChanges {
            modelContext.rollback()
        }
    }

    /// Saves, or discards every pending edit if the save fails, so no later save can persist a failed operation.
    private func commit() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: Lookups

    private func columns() throws -> [BoardColumn] {
        try modelContext.fetch(FetchDescriptor<BoardColumn>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    private func tasks(in columnID: UUID, includingArchived: Bool = false) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.columnID == columnID }, sortBy: [SortDescriptor(\.sortOrder)])
        let all = try modelContext.fetch(descriptor)
        return includingArchived ? all : all.filter { $0.archivedAt == nil }
    }

    private func subtasks(of taskID: UUID) throws -> [SubtaskItem] {
        let descriptor = FetchDescriptor<SubtaskItem>(
            predicate: #Predicate { $0.taskID == taskID }, sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor)
    }

    private func requireColumn(_ id: UUID) throws -> BoardColumn {
        let descriptor = FetchDescriptor<BoardColumn>(predicate: #Predicate { $0.id == id })
        guard let column = try modelContext.fetch(descriptor).first else { throw TaskBoardError.unknownColumn }
        return column
    }

    private func requireTask(_ id: UUID) throws -> TaskItem {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        guard let task = try modelContext.fetch(descriptor).first else { throw TaskBoardError.unknownTask }
        return task
    }

    private func requireSubtask(_ id: UUID) throws -> SubtaskItem {
        let descriptor = FetchDescriptor<SubtaskItem>(predicate: #Predicate { $0.id == id })
        guard let subtask = try modelContext.fetch(descriptor).first else { throw TaskBoardError.unknownSubtask }
        return subtask
    }
}
