import Foundation
import SwiftData
import Synchronization

/// The Kanban board (spec §7.8–§7.10, §8.5): columns, tasks, subtasks, ordering, and the completion rule.
/// One instance per container, like the other services, so every board write goes through one serial context.
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
        guard try modelContext.fetchCount(FetchDescriptor<BoardColumn>()) == 0 else { return }
        for (index, name) in Self.defaultColumnNames.enumerated() {
            modelContext.insert(BoardColumn(name: name, sortOrder: index, isSystem: true, now: now))
        }
        try commit()
    }

    /// Adds a custom column just before the done column, so "last column = done" keeps its meaning.
    @discardableResult
    public func createColumn(named name: String, now: Date) throws -> UUID {
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskBoardError.emptyColumnName }
        let column = try requireColumn(id)
        column.name = trimmed
        column.updatedAt = now
        try commit()
    }

    /// Moves a column to `index` in the board order. If the done column changes, completion is re-applied.
    public func moveColumn(_ id: UUID, to index: Int, now: Date) throws {
        var ordered = try columns()
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { throw TaskBoardError.unknownColumn }
        let column = ordered.remove(at: from)
        ordered.insert(column, at: min(max(index, 0), ordered.count))
        renumber(ordered, now: now)
        try applyCompletionRule(doneColumnID: ordered.last?.id, now: now)
        try commit()
    }

    /// Spec §8.5: a column with tasks is deleted only after its tasks move to `destination`, in the same save.
    public func deleteColumn(_ id: UUID, movingTasksTo destination: UUID, now: Date) throws {
        let column = try requireColumn(id)
        guard !column.isSystem else { throw TaskBoardError.systemColumnIsPermanent }
        guard destination != id else { throw TaskBoardError.destinationIsSource }
        _ = try requireColumn(destination)
        var key = try tasks(in: destination).last?.sortOrder ?? 0
        for task in try tasks(in: id, includingArchived: true) {
            key += 1
            task.columnID = destination
            task.sortOrder = key
            task.updatedAt = now
        }
        modelContext.delete(column)
        let remaining = try columns().filter { $0.id != id }
        renumber(remaining, now: now)
        try applyCompletionRule(doneColumnID: remaining.last?.id, now: now)
        try commit()
    }

    // MARK: Tasks

    /// Adds a task at the bottom of `columnID`, or of the first column when nil.
    @discardableResult
    public func createTask(_ draft: TaskDraft, in columnID: UUID? = nil, now: Date) throws -> UUID {
        try draft.validate()
        try requireWishlistLink(draft.linkedWishlistItemID)
        let ordered = try columns()
        guard let column = columnID.flatMap({ id in ordered.first { $0.id == id } }) ?? ordered.first else {
            throw TaskBoardError.unknownColumn
        }
        let key = SortKey.between(try tasks(in: column.id).last?.sortOrder, nil) ?? 1
        let task = TaskItem(
            title: draft.trimmedTitle, columnID: column.id, priority: draft.priority, sortOrder: key, now: now)
        apply(draft, to: task)
        task.completedAt = column.id == ordered.last?.id ? now : nil
        modelContext.insert(task)
        try commit()
        return task.id
    }

    public func updateTask(_ id: UUID, with draft: TaskDraft, now: Date) throws {
        try draft.validate()
        try requireWishlistLink(draft.linkedWishlistItemID)
        let task = try requireTask(id)
        task.title = draft.trimmedTitle
        task.priority = draft.priority
        apply(draft, to: task)
        task.updatedAt = now
        try commit()
    }

    /// Moves a task to position `index` of `columnID` (0 = top), among the column's other visible tasks.
    public func moveTask(_ id: UUID, to columnID: UUID, at index: Int, now: Date) throws {
        let task = try requireTask(id)
        _ = try requireColumn(columnID)
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
        let doneColumnID = try columns().last?.id
        applyCompletion(to: task, doneColumnID: doneColumnID, now: now)
        try commit()
    }

    /// Completing moves the task to the bottom of the done column; reopening moves it to the bottom of the first.
    public func setTaskCompleted(_ completed: Bool, task id: UUID, now: Date) throws {
        let ordered = try columns()
        guard let target = completed ? ordered.last : ordered.first else { throw TaskBoardError.unknownColumn }
        let task = try requireTask(id)
        guard (task.completedAt != nil) != completed else { return }
        let count = try tasks(in: target.id).filter { $0.id != id }.count
        try moveTask(id, to: target.id, at: count, now: now)
    }

    public func setTaskArchived(_ archived: Bool, task id: UUID, now: Date) throws {
        let task = try requireTask(id)
        task.archivedAt = archived ? now : nil
        task.updatedAt = now
        try commit()
    }

    /// Deletes the task and its subtasks in one save. Tasks are not financial history (spec §8 covers money only).
    public func deleteTask(_ id: UUID) throws {
        let task = try requireTask(id)
        for subtask in try subtasks(of: id) {
            modelContext.delete(subtask)
        }
        modelContext.delete(task)
        try commit()
    }

    // MARK: Subtasks

    @discardableResult
    public func addSubtask(titled title: String, to taskID: UUID, now: Date) throws -> UUID {
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
        let subtask = try requireSubtask(id)
        subtask.isCompleted = completed
        subtask.updatedAt = now
        try commit()
    }

    public func renameSubtask(_ id: UUID, to title: String, now: Date) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskBoardError.emptyTitle }
        let subtask = try requireSubtask(id)
        subtask.title = trimmed
        subtask.updatedAt = now
        try commit()
    }

    /// Moves a subtask to `index` within its task; subtask lists are short, so they are simply renumbered.
    public func moveSubtask(_ id: UUID, to index: Int, now: Date) throws {
        let subtask = try requireSubtask(id)
        var ordered = try subtasks(of: subtask.taskID).filter { $0.id != id }
        ordered.insert(subtask, at: min(max(index, 0), ordered.count))
        for (offset, item) in ordered.enumerated() where item.sortOrder != Double(offset + 1) {
            item.sortOrder = Double(offset + 1)
            item.updatedAt = now
        }
        try commit()
    }

    public func deleteSubtask(_ id: UUID) throws {
        modelContext.delete(try requireSubtask(id))
        try commit()
    }

    // MARK: Helpers

    private func apply(_ draft: TaskDraft, to task: TaskItem) {
        let notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes?.isEmpty == false ? notes : nil
        task.dueDate = draft.dueDate
        task.linkedWishlistItemID = draft.linkedWishlistItemID
    }

    private func renumber(_ ordered: [BoardColumn], now: Date) {
        for (index, column) in ordered.enumerated() where column.sortOrder != index {
            column.sortOrder = index
            column.updatedAt = now
        }
    }

    private func applyCompletion(to task: TaskItem, doneColumnID: UUID?, now: Date) {
        let isDone = task.columnID == doneColumnID
        if isDone, task.completedAt == nil {
            task.completedAt = now
        } else if !isDone, task.completedAt != nil {
            task.completedAt = nil
        }
    }

    private func applyCompletionRule(doneColumnID: UUID?, now: Date) throws {
        for task in try modelContext.fetch(FetchDescriptor<TaskItem>()) {
            applyCompletion(to: task, doneColumnID: doneColumnID, now: now)
        }
    }

    private func requireWishlistLink(_ id: UUID?) throws {
        guard let id else { return }
        let descriptor = FetchDescriptor<WishlistItem>(predicate: #Predicate { $0.id == id })
        guard try modelContext.fetchCount(descriptor) > 0 else { throw TaskBoardError.unknownWishlistItem }
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
