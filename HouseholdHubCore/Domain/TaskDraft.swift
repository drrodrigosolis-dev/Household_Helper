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
    /// A due time is a time on the due day (Sprint 26): without a due date it is refused, not dropped, so a caller
    /// never loses a time it meant to keep. Clearing the date means clearing the time in the same draft.
    case timeNeedsDueDate
    /// A due time is minutes after local midnight, 0...1439.
    case invalidDueTime
}

/// A time of day as minutes after local midnight (Sprint 26): task due times and the reminder default time.
public enum TimeOfDay {
    public static let minutesPerDay = 24 * 60
    /// 9:00, the reminder default time before the user sets one.
    public static let defaultReminderMinutes = 9 * 60

    public static func isValid(_ minutes: Int) -> Bool {
        (0..<minutesPerDay).contains(minutes)
    }

    /// The minutes after midnight of `date`'s wall-clock time in `calendar`.
    public static func minutes(of date: Date, calendar: HouseholdCalendar) -> Int {
        let parts = calendar.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// `minutes` after midnight on the day of `day` in `calendar`. On a day the time doesn't exist (spring forward)
    /// it is the next valid time; on a day it happens twice (fall back), the first. Never nil for a valid day.
    public static func date(minutes: Int, onDayOf day: Date, calendar: HouseholdCalendar) -> Date {
        let clamped = min(max(minutes, 0), minutesPerDay - 1)
        let start = calendar.startOfDay(for: day)
        let found = calendar.calendar.date(
            bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: start,
            matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first, direction: .forward)
        return found ?? start.addingTimeInterval(TimeInterval(clamped * 60))
    }
}

/// The user-editable fields of a task. Column, order, and completion change only through moves (spec §7.8).
public struct TaskDraft: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var priority: Priority
    public var dueDate: Date?
    /// Sprint 26: the due time, minutes after local midnight on the due day; nil = no time. Needs a due date.
    public var dueTimeMinutes: Int?
    public var linkedWishlistItemID: UUID?
    /// A transaction the task is about (spec §2.1, §7.8); a link to one that no longer exists is dropped on save.
    public var linkedTransactionID: UUID?
    /// How the task repeats (Sprint 13); nil = it doesn't. Needs a due date.
    public var recurrence: RecurrenceRule?
    /// The zone the rule's days are counted in.
    public var timeZone: TimeZone

    public init(
        title: String, notes: String? = nil, priority: Priority = .medium, dueDate: Date? = nil,
        dueTimeMinutes: Int? = nil, linkedWishlistItemID: UUID? = nil, linkedTransactionID: UUID? = nil,
        recurrence: RecurrenceRule? = nil, timeZone: TimeZone = .current
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.dueTimeMinutes = dueTimeMinutes
        self.linkedWishlistItemID = linkedWishlistItemID
        self.linkedTransactionID = linkedTransactionID
        self.recurrence = recurrence
        self.timeZone = timeZone
    }

    public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func validate() throws {
        guard !trimmedTitle.isEmpty else { throw TaskBoardError.emptyTitle }
        if let dueTimeMinutes {
            guard dueDate != nil else { throw TaskBoardError.timeNeedsDueDate }
            guard TimeOfDay.isValid(dueTimeMinutes) else { throw TaskBoardError.invalidDueTime }
        }
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
