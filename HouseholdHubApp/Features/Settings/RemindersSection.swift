import SwiftUI

/// Settings › Reminders (Sprint 14): two switches, both off until turned on. Turning one on asks for notification
/// permission; if it is refused the switch goes back off and says where to allow it.
struct RemindersSection: View {
    @Environment(\.services) private var services
    @AppStorage(ReminderSync.tasksKey) private var tasksDue = false
    @AppStorage(ReminderSync.billsKey) private var billsDue = false
    @State private var permissionDenied = false

    var body: some View {
        Section {
            Toggle("Tasks due today", isOn: binding($tasksDue))
                .accessibilityIdentifier("settings.remindTasks")
            Toggle("Bills due tomorrow", isOn: binding($billsDue))
                .accessibilityIdentifier("settings.remindBills")
            if permissionDenied {
                Text("Notifications are off for Household Hub. Allow them in the Settings app to get reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Reminders arrive at 9:00 on this device. They show names only, never amounts.")
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
