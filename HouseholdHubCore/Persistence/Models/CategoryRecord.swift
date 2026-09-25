import Foundation
import SwiftData

extension SchemaV1 {
    /// A user-defined or system category (spec §7.3). Named `CategoryRecord` because `Category` collides with the
    /// ObjectiveC module's type wherever Foundation is imported. Referenced categories are archived, never deleted.
    @Model
    public final class CategoryRecord {
        @Attribute(.unique) public var id: UUID
        public var name: String
        /// SF Symbol name.
        public var icon: String
        public var color: ColorToken
        public var kindRawValue: String
        public var sortOrder: Int
        public var isSystem: Bool
        public var isArchived: Bool
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(), name: String, icon: String, color: ColorToken, kind: CategoryKind, sortOrder: Int,
            isSystem: Bool = false, now: Date
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.color = color
            self.kindRawValue = kind.rawValue
            self.sortOrder = sortOrder
            self.isSystem = isSystem
            self.isArchived = false
            self.createdAt = now
            self.updatedAt = now
        }

        public var kind: CategoryKind {
            get { CategoryKind(rawValue: kindRawValue) ?? .both }
            set { kindRawValue = newValue.rawValue }
        }
    }
}

public typealias CategoryRecord = SchemaV1.CategoryRecord
