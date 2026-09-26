import Foundation
import SwiftData

extension SchemaV1 {
    /// A Kanban column (spec §7.10). Integer order, renumbered after every reorder.
    @Model
    public final class BoardColumn {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var sortOrder: Int
        public var isSystem: Bool
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), name: String, sortOrder: Int, isSystem: Bool = false, now: Date) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
            self.isSystem = isSystem
            self.createdAt = now
            self.updatedAt = now
        }
    }

    /// A task card (spec §7.8). Named `TaskItem` because `Task` is Swift concurrency's type.
    @Model
    public final class TaskItem {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var notes: String?
        public var columnID: UUID
        public var priorityRawValue: String
        public var dueDate: Date?
        public var completedAt: Date?
        /// Position within the column; a move takes the midpoint of its new neighbours (spec §7.8).
        public var sortOrder: Double
        public var linkedWishlistItemID: UUID?
        public var linkedTransactionID: UUID?
        public var archivedAt: Date?
        /// A repeating task's rule (Sprint 13), JSON-encoded like `RecurringTransaction.ruleData`; nil = no repeat.
        /// Only the open task of a series carries it: completing it hands the rule to the next task.
        public var recurrenceRuleData: Data?
        /// Calendar context for the rule, e.g. "America/Vancouver"; set exactly when `recurrenceRuleData` is.
        public var recurrenceTimeZoneIdentifier: String?
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), title: String, columnID: UUID, priority: Priority, sortOrder: Double, now: Date
        ) {
            self.id = id
            self.title = title
            self.columnID = columnID
            self.priorityRawValue = priority.rawValue
            self.sortOrder = sortOrder
            self.createdAt = now
            self.updatedAt = now
        }

        public var priority: Priority {
            get { Priority(rawValue: priorityRawValue) ?? .medium }
            set { priorityRawValue = newValue.rawValue }
        }

        /// The repeat rule, or nil when the task doesn't repeat or the stored rule can't be read.
        public var recurrence: RecurrenceRule? {
            recurrenceRuleData.flatMap { try? RecurrenceRule.decoded(from: $0) }
        }
    }

    /// A checklist step of a task (spec §7.9), linked by `taskID` and deleted with its task.
    @Model
    public final class SubtaskItem {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var isCompleted: Bool
        public var sortOrder: Double
        public var taskID: UUID
        public var createdAt: Date
        public var updatedAt: Date

        public init(id: UUID = UUID(), title: String, taskID: UUID, sortOrder: Double, now: Date) {
            self.id = id
            self.title = title
            self.isCompleted = false
            self.sortOrder = sortOrder
            self.taskID = taskID
            self.createdAt = now
            self.updatedAt = now
        }
    }
}

public typealias BoardColumn = SchemaV1.BoardColumn
public typealias TaskItem = SchemaV1.TaskItem
public typealias SubtaskItem = SchemaV1.SubtaskItem
