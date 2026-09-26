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

    public init(taskID: UUID, title: String, dueDate: Date) {
        self.taskID = taskID
        self.title = title
        self.dueDate = dueDate
    }
}

/// Which reminders the user turned on, and the words to use (the app passes localized strings; Core stays UI-free).
public struct ReminderSettings: Equatable, Sendable {
    public var tasksDue: Bool
    public var billsDue: Bool
    /// Local hour of day reminders fire at.
    public var hour: Int

    public init(tasksDue: Bool, billsDue: Bool, hour: Int = 9) {
        self.tasksDue = tasksDue
        self.billsDue = billsDue
        self.hour = hour
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

/// Deterministic reminder plan (Sprint 14): a task due today reminds at `hour` on its due day; an upcoming recurring
/// expense reminds at `hour` the day before. Past fire times are skipped. At most `limit` reminders, soonest first
/// (iOS keeps at most 64 pending per app).
public struct ReminderPlanner: Sendable {
    public static let defaultLimit = 60

    public init() {}

    public func plan(
        tasks: [TaskReminderSource], bills: [UpcomingOccurrence], settings: ReminderSettings,
        wording: ReminderWording, now: Date, calendar: HouseholdCalendar, limit: Int = defaultLimit
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        if settings.tasksDue {
            for task in tasks {
                guard let fire = fireDate(onDayOf: task.dueDate, offsetDays: 0, hour: settings.hour, calendar: calendar)
                else { continue }
                planned.append(
                    PlannedReminder(
                        id: "task-\(task.taskID.uuidString)", kind: .taskDue, title: wording.taskTitle,
                        body: wording.taskBody(task.title), fireDate: fire))
            }
        }
        if settings.billsDue {
            for bill in bills where bill.type == .expense {
                guard let fire = fireDate(onDayOf: bill.date, offsetDays: -1, hour: settings.hour, calendar: calendar)
                else { continue }
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

    /// `hour`:00 local time on the day of `date` shifted by `offsetDays`.
    private func fireDate(onDayOf date: Date, offsetDays: Int, hour: Int, calendar: HouseholdCalendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        guard let shifted = calendar.calendar.date(byAdding: .day, value: offsetDays, to: day) else { return nil }
        let parts = calendar.calendar.dateComponents([.year, .month, .day], from: shifted)
        return calendar.calendar.date(
            from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: hour))
    }
}
