import Foundation

public enum TaskBoardError: Error, Equatable, Sendable {
    case unknownColumn
    case unknownTask
    case unknownSubtask
    case unknownWishlistItem
    case emptyTitle
    case emptyColumnName
    /// The seeded columns anchor the board (the last one is "done"); they can be renamed and moved, not deleted.
    case systemColumnIsPermanent
    case destinationIsSource
}

/// The user-editable fields of a task. Column, order, and completion change only through moves (spec §7.8).
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var priority: Priority
    public var dueDate: Date?
    public var linkedWishlistItemID: UUID?

    public init(
        title: String, notes: String? = nil, priority: Priority = .medium, dueDate: Date? = nil,
        linkedWishlistItemID: UUID? = nil
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.linkedWishlistItemID = linkedWishlistItemID
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func validate() throws {
        guard !trimmedTitle.isEmpty else { throw TaskBoardError.emptyTitle }
    }
}

/// Ordering keys for manual reordering (spec §7.8): a new position takes the midpoint of its neighbours; when two
/// neighbours get too close to split, the caller renumbers the list and asks again.
public enum SortKey {
    /// Smallest gap still split; below it the list is renumbered 1, 2, 3, … first.
    public static let minimumGap = 1e-6

    /// The key for inserting between `before` and `after` (either may be absent), or nil when the gap is too small.
    public static func between(_ before: Double?, _ after: Double?) -> Double? {
        switch (before, after) {
        case (nil, nil): return 1
        case (let low?, nil): return low + 1
        case (nil, let high?): return high - 1
        case (let low?, let high?):
            guard high - low > minimumGap else { return nil }
            return (low + high) / 2
        }
    }
}
