import HouseholdHubCore
import SwiftUI

/// Settings › Reminders (Sprint 14): two switches, both off until turned on. Turning one on asks for notification
/// permission; if it is refused the switch goes back off and says where to allow it. Sprint 23 F7 adds budget alerts,
/// on by default (they arrive once notifications are allowed). Sprint 26 adds the "Reminder default time" (9:00 until
/// changed) for tasks without a time and for bills; changing it reschedules, like the switches.
struct RemindersSection: View {
    @Environment(\.services) private var services
    @AppStorage(ReminderSync.tasksKey) private var tasksDue = false
    @AppStorage(ReminderSync.billsKey) private var billsDue = false
    @AppStorage(ReminderSync.budgetAlertsKey) private var budgetAlerts = true
    @AppStorage(ReminderSync.defaultTimeKey) private var defaultTime = TimeOfDay.defaultReminderMinutes
    @State private var permissionDenied = false

    private var calendar: HouseholdCalendar { HouseholdCalendar(timeZone: .current) }

    /// The stored minutes, or 9:00 if the stored value can't be a time of day.
    private var defaultMinutes: Int {
        TimeOfDay.isValid(defaultTime) ? defaultTime : TimeOfDay.defaultReminderMinutes
    }

    private var defaultTimeText: String {
        TimeOfDay.pickerDate(minutes: defaultMinutes, calendar: calendar).formatted(date: .omitted, time: .shortened)
    }

    /// Built on a fixed day without a clock change (Sprint 26 review S1), so 2:30 never reads as 3:00.
    private var defaultTimeBinding: Binding<Date> {
        Binding(
            get: { TimeOfDay.pickerDate(minutes: defaultMinutes, calendar: calendar) },
            set: { date in defaultTime = TimeOfDay.minutes(of: date, calendar: calendar) })
    }

    var body: some View {
        Section {
            Toggle("Tasks due today", isOn: binding($tasksDue))
                .accessibilityIdentifier("settings.remindTasks")
            Toggle("Bills due tomorrow", isOn: binding($billsDue))
                .accessibilityIdentifier("settings.remindBills")
            DatePicker("Reminder default time", selection: defaultTimeBinding, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("settings.reminderDefaultTime")
            Toggle("Budget alerts", isOn: binding($budgetAlerts))
                .accessibilityIdentifier("settings.budgetAlerts")
            if permissionDenied {
                Text("Notifications are off for Household Hub. Allow them in the Settings app to get reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Reminders")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("A task with a time reminds at that time. Other tasks and bills remind at \(defaultTimeText).")
                    .accessibilityIdentifier("settings.reminderDefaultTimeNote")
                Text("Reminders arrive on this device. They show names only, never amounts.")
                Text("Budget alerts come once a month per category, at 80 and at 100 percent of its budget.")
            }
        }
        .onChange(of: defaultTime) {
            // Refreshes run one after another and a superseded one adds nothing (Sprint 26 review S3).
            Task { await ReminderSync.refresh(services) }
        }
    }

    private func binding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { isOn in
                value.wrappedValue = isOn
                Task {
                    if isOn, !(await ReminderSync.requestPermission()) {
                        value.wrappedValue = false
                        permissionDenied = true
                    }
                    await ReminderSync.refresh(services)
                }
            })
    }
}
