import HouseholdHubCore
import UserNotifications

/// Local reminders (Sprint 14, owner decision 23): tasks due today and recurring bills due tomorrow, each kind behind
/// its own switch (off until turned on), on this device only: the switches are device preferences, not backed-up
/// data. No push server; nothing leaves the device. Rebuilt from the store whenever the app goes to the background or
/// a setting changes, so edits are picked up without tracking each one. Sprint 26: a task with a due time reminds at
/// it; other tasks and bills at the "Reminder default time" (9:00 until changed), also a device preference.
///
/// Sprint 23 F7: budget alerts when a category reaches 80 % and 100 % of its budget, once each per category per
/// month. On by default, but they only arrive once notifications are allowed (turning any switch on asks). Which ones
/// were sent is remembered on this device, like the switches.
enum ReminderSync {
    static let tasksKey = "reminders.tasksDue"
    static let billsKey = "reminders.billsDue"
    static let budgetAlertsKey = "reminders.budgetAlerts"
    /// The "already sent" keys of this month's budget alerts (`BudgetAlertPlanner.key`).
    static let budgetAlertsSentKey = "reminders.budgetAlertsSent"
    /// Budget alerts default to on (Sprint 23 F7); `bool(forKey:)` would read a missing value as off.
    static var budgetAlertsOn: Bool {
        UserDefaults.standard.object(forKey: budgetAlertsKey) as? Bool ?? true
    }
    /// Sprint 26: the "Reminder default time", minutes after midnight (540 = 9:00 until the user sets one). A task
    /// without a time and every bill remind at it; a task with a time reminds at its own.
    static let defaultTimeKey = "reminders.defaultTime"
    static var defaultTimeMinutes: Int {
        let stored = UserDefaults.standard.object(forKey: defaultTimeKey) as? Int
        return stored.flatMap { TimeOfDay.isValid($0) ? $0 : nil } ?? TimeOfDay.defaultReminderMinutes
    }
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
            tasksDue: defaults.bool(forKey: tasksKey), billsDue: defaults.bool(forKey: billsKey),
            defaultTimeMinutes: defaultTimeMinutes)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter(isOurs)
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let budgetAlerts = budgetAlertsOn
        guard settings.tasksDue || settings.billsDue || budgetAlerts else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let now = Date.now
        let calendar = HouseholdCalendar(timeZone: .current)
        if budgetAlerts {
            await sendBudgetAlerts(services, now: now, calendar: calendar)
        }
        guard settings.tasksDue || settings.billsDue else { return }
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

    /// Budget alerts due now (Sprint 23 F7), delivered a few seconds later so they show once the app is in the
    /// background. `refresh` never removes them: each is sent once, and its key is remembered as soon as it is
    /// planned, so an alert never arrives twice.
    @MainActor
    private static func sendBudgetAlerts(_ services: AppServices, now: Date, calendar: HouseholdCalendar) async {
        let report = try? await services.transactions.budgetAlertSources(month: now, calendar: calendar)
        guard let sources = report, !sources.isEmpty else { return }
        let defaults = UserDefaults.standard
        let sent = Set(defaults.stringArray(forKey: budgetAlertsSentKey) ?? [])
        let month = BudgetMonth(containing: now, calendar: calendar)
        let plan = BudgetAlertPlanner().plan(sources, month: month, alreadySent: sent)
        defaults.set(plan.sentKeys, forKey: budgetAlertsSentKey)
        let center = UNUserNotificationCenter.current()
        for alert in plan.alerts {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Budget alert")
            content.body = budgetAlertBody(alert)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }
    }

    /// The category's name and the threshold, never an amount.
    static func budgetAlertBody(_ alert: PlannedBudgetAlert) -> String {
        let name = alert.categoryName
        switch alert.threshold {
        case .eighty:
            let share = alert.threshold.rawValue.formatted(.percent)
            return String(localized: "\(name) is at \(share) of its budget this month.")
        case .hundred:
            return String(localized: "\(name) has reached its budget this month.")
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
