import SwiftUI

/// Settings › Reminders (Sprint 14): two switches, both off until turned on. Turning one on asks for notification
/// permission; if it is refused the switch goes back off and says where to allow it. Sprint 23 F7 adds budget alerts,
/// on by default (they arrive once notifications are allowed).
struct RemindersSection: View {
    @Environment(\.services) private var services
    @AppStorage(ReminderSync.tasksKey) private var tasksDue = false
    @AppStorage(ReminderSync.billsKey) private var billsDue = false
    @AppStorage(ReminderSync.budgetAlertsKey) private var budgetAlerts = true
    @State private var permissionDenied = false

    var body: some View {
        Section {
            Toggle("Tasks due today", isOn: binding($tasksDue))
                .accessibilityIdentifier("settings.remindTasks")
            Toggle("Bills due tomorrow", isOn: binding($billsDue))
                .accessibilityIdentifier("settings.remindBills")
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
                Text("Reminders arrive at 9:00 on this device. They show names only, never amounts.")
                Text("Budget alerts come once a month per category, at 80 and at 100 percent of its budget.")
            }
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
