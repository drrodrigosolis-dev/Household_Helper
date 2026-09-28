import Foundation

/// A local notification to schedule (Sprint 14 decisions 3–5). Bodies never carry amounts: notifications can show on
/// the Lock Screen.
public struct PlannedReminder: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case taskDue
        case billDue
    }

    /// Stable per task or occurrence, so rescheduling replaces rather than duplicates.
    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let fireDate: Date

    public init(id: String, kind: Kind, title: String, body: String, fireDate: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

/// An open task with a due date, as the planner needs it.
public struct TaskReminderSource: Equatable, Sendable {
    public let taskID: UUID
    public let title: String
    public let dueDate: Date
    /// Sprint 26: the task's due time, minutes after local midnight; nil = remind at the default time.
    public let dueTimeMinutes: Int?

    public init(taskID: UUID, title: String, dueDate: Date, dueTimeMinutes: Int? = nil) {
        self.taskID = taskID
        self.title = title
        self.dueDate = dueDate
        self.dueTimeMinutes = dueTimeMinutes
    }
}

/// Which reminders the user turned on, and the words to use (the app passes localized strings; Core stays UI-free).
public struct ReminderSettings: Equatable, Sendable {
    public var tasksDue: Bool
    public var billsDue: Bool
    /// Sprint 26: the "Reminder default time", minutes after local midnight (9:00 until the user sets one). A task
    /// without a time and every bill remind at it; an invalid value reads as 9:00.
    public var defaultTimeMinutes: Int

    public init(tasksDue: Bool, billsDue: Bool, defaultTimeMinutes: Int = TimeOfDay.defaultReminderMinutes) {
        self.tasksDue = tasksDue
        self.billsDue = billsDue
        self.defaultTimeMinutes = defaultTimeMinutes
    }
}

public struct ReminderWording: Sendable {
    public let taskTitle: String
    public let taskBody: @Sendable (String) -> String
    public let billTitle: String
    public let billBody: @Sendable (String?) -> String

    public init(
        taskTitle: String, taskBody: @escaping @Sendable (String) -> String, billTitle: String,
        billBody: @escaping @Sendable (String?) -> String
    ) {
        self.taskTitle = taskTitle
        self.taskBody = taskBody
        self.billTitle = billTitle
        self.billBody = billBody
    }
}

/// Deterministic reminder plan (Sprint 14): a task reminds on its due day, at its due time when it has one and at the
/// default time otherwise (Sprint 26); an upcoming recurring bill reminds at the default time the day before (Sprint
/// 22: not a recurring purchase). Times go through `HouseholdCalendar`: a time a spring-forward day skips fires at the
/// next valid time, a time a fall-back day repeats fires once, the first time. Past fire times are skipped. At most
/// `limit` reminders, soonest first (iOS keeps at most 64 pending per app).
public struct ReminderPlanner: Sendable {
    public static let defaultLimit = 60

    public init() {}

    public func plan(
        tasks: [TaskReminderSource], bills: [UpcomingOccurrence], settings: ReminderSettings,
        wording: ReminderWording, now: Date, calendar: HouseholdCalendar, limit: Int = defaultLimit
    ) -> [PlannedReminder] {
        var defaultTime = settings.defaultTimeMinutes
        if !TimeOfDay.isValid(defaultTime) {
            defaultTime = TimeOfDay.defaultReminderMinutes
        }
        var planned: [PlannedReminder] = []
        if settings.tasksDue {
            for task in tasks {
                var time = defaultTime
                if let own = task.dueTimeMinutes, TimeOfDay.isValid(own) {
                    time = own
                }
                let fire = fireDate(onDayOf: task.dueDate, offsetDays: 0, minutes: time, calendar: calendar)
                guard let fire else { continue }
                planned.append(
                    PlannedReminder(
                        id: "task-\(task.taskID.uuidString)", kind: .taskDue, title: wording.taskTitle,
                        body: wording.taskBody(task.title), fireDate: fire))
            }
        }
        if settings.billsDue {
            // A recurring purchase is something you do, not something you owe: no "due" reminder (Sprint 22).
            for bill in bills where bill.type == .expense && bill.kind == .bill {
                let fire = fireDate(onDayOf: bill.date, offsetDays: -1, minutes: defaultTime, calendar: calendar)
                guard let fire else { continue }
                planned.append(
                    PlannedReminder(
                        id: "bill-\(bill.id)", kind: .billDue, title: wording.billTitle,
                        body: wording.billBody(bill.title), fireDate: fire))
            }
        }
        let future = planned.filter { $0.fireDate > now }
        let soonest = future.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(soonest.prefix(max(0, limit)))
    }

    /// `minutes` after local midnight on the day of `date` shifted by `offsetDays` (the next valid time on a day that
    /// skips it).
    private func fireDate(onDayOf date: Date, offsetDays: Int, minutes: Int, calendar: HouseholdCalendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        guard let shifted = calendar.calendar.date(byAdding: .day, value: offsetDays, to: day) else { return nil }
        return TimeOfDay.date(minutes: minutes, onDayOf: shifted, calendar: calendar)
    }
}
