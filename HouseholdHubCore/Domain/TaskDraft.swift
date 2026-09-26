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
    /// A repeating task needs a due date: the next one is due on the rule's next date after it (Sprint 13).
    case repeatNeedsDueDate
    case invalidRepeat
    /// A completed task is history: its repeat has moved on to the next task, and giving it a new one would start a
    /// second series (Sprint 13 data-safety review).
    case repeatOnCompletedTask
}

/// The user-editable fields of a task. Column, order, and completion change only through moves (spec §7.8).
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var priority: Priority
    public var dueDate: Date?
    public var linkedWishlistItemID: UUID?
    /// A transaction the task is about (spec §2.1, §7.8); a link to one that no longer exists is dropped on save.
    public var linkedTransactionID: UUID?
    /// How the task repeats (Sprint 13); nil = it doesn't. Needs a due date.
    public var recurrence: RecurrenceRule?
    /// The zone the rule's days are counted in.
    public var timeZone: TimeZone

    public init(
        title: String, notes: String? = nil, priority: Priority = .medium, dueDate: Date? = nil,
        linkedWishlistItemID: UUID? = nil, linkedTransactionID: UUID? = nil, recurrence: RecurrenceRule? = nil,
        timeZone: TimeZone = .current
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.linkedWishlistItemID = linkedWishlistItemID
        self.linkedTransactionID = linkedTransactionID
        self.recurrence = recurrence
        self.timeZone = timeZone
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func validate() throws {
        guard !trimmedTitle.isEmpty else { throw TaskBoardError.emptyTitle }
        guard let recurrence else { return }
        guard dueDate != nil else { throw TaskBoardError.repeatNeedsDueDate }
        do {
            try recurrence.validate()
        } catch {
            throw TaskBoardError.invalidRepeat
        }
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
            let middle = (low + high) / 2
            // Both checks: the gap test catches near-ties, the ordering test catches rounding at large magnitudes.
            guard high - low > minimumGap, low < middle, middle < high else { return nil }
            return middle
        }
    }
}

/// The repeat choices the task editor offers (Sprint 13 decision 5), each read off the due date: weekly on its weekday,
/// monthly on its day, yearly on its month and day. A stored rule the editor can't express reads as nil here, and
/// the editor keeps it as it is.
public enum TaskRepeat: String, CaseIterable, Sendable {
    case daily
    case weekly
    case everyTwoWeeks
    case monthly
    case yearly

    public func rule(dueDate: Date, calendar: HouseholdCalendar) -> RecurrenceRule {
        let parts = calendar.calendar.dateComponents([.weekday, .day, .month], from: dueDate)
        let weekday = parts.weekday ?? 1
        switch self {
        case .daily: return .daily(interval: 1)
        case .weekly: return .weekly(interval: 1, weekday: weekday)
        case .everyTwoWeeks: return .weekly(interval: 2, weekday: weekday)
        case .monthly: return .monthlyOnDay(day: parts.day ?? 1)
        case .yearly: return .yearly(month: parts.month ?? 1, day: parts.day ?? 1)
        }
    }

    /// The choice that produces `rule` for a task due on `dueDate`, or nil when none does.
    public init?(rule: RecurrenceRule, dueDate: Date, calendar: HouseholdCalendar) {
        guard let match = Self.allCases.first(where: { $0.rule(dueDate: dueDate, calendar: calendar) == rule }) else {
            return nil
        }
        self = match
    }
}
