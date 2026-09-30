import Foundation
import SwiftData

extension SchemaV1 {
    /// FROZEN: `TaskItem` as installed on the owner's iPhone with SchemaV1 (`063a510`) and shared unchanged by SchemaV2
    /// (`fd7e67e`), SchemaV3 (`8a9ec36`) and SchemaV4. Kept only so SwiftData can recognize and migrate a V1 to V4
    /// store; never used by the app. Do not edit: the store's version hash depends on it.
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
    }
}
