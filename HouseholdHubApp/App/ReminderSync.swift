import HouseholdHubCore
import UserNotifications

/// Local reminders (Sprint 14, owner decision 23): tasks due today and recurring bills due tomorrow, at 9:00, each
/// kind behind its own switch (off until turned on), on this device only: the switches are device preferences, not
/// backed-up data. No push server; nothing leaves the device. Rebuilt from the store whenever the app goes to the
/// background or a switch changes, so edits are picked up without tracking each one.
enum ReminderSync {
    static let tasksKey = "reminders.tasksDue"
    static let billsKey = "reminders.billsDue"
    /// How far ahead bills are looked at; the plan keeps the 60 soonest reminders anyway.
    private static let billDays = 62

    private static func isOurs(_ identifier: String) -> Bool {
        identifier.hasPrefix("task-") || identifier.hasPrefix("bill-")
    }

    /// Asks for permission the first time a switch is turned on; false when the user declines (or declined before).
    @MainActor
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    @MainActor
    static func refresh(_ services: AppServices?) async {
        // UI tests run on a throwaway store and must never touch this device's notifications.
        guard !ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting), let services else { return }
        let defaults = UserDefaults.standard
        let settings = ReminderSettings(
            tasksDue: defaults.bool(forKey: tasksKey), billsDue: defaults.bool(forKey: billsKey))
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(isOurs)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard settings.tasksDue || settings.billsDue else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let now = Date.now
        let calendar = HouseholdCalendar(timeZone: .current)
        let tasks = (try? await services.board.reminderSources()) ?? []
        let upcoming = try? await services.transactions.upcomingOccurrences(
            now: now, calendar: calendar, days: billDays)
        let bills = upcoming ?? []
        let plan = ReminderPlanner().plan(
            tasks: tasks, bills: bills, settings: settings, wording: wording, now: now, calendar: calendar)
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
            let parts = calendar.calendar.dateComponents(fields, from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    /// Names only, never amounts (Sprint 14 decision 5): notifications can show on the Lock Screen.
    private static var wording: ReminderWording {
        ReminderWording(
            taskTitle: String(localized: "Task due today"),
            taskBody: { title in title },
            billTitle: String(localized: "Bill due tomorrow"),
            billBody: { name in
                guard let name, !name.isEmpty else { return String(localized: "A recurring bill is due tomorrow.") }
                return String(localized: "\(name) is due tomorrow.")
            })
    }
}
