import HouseholdHubCore
import SwiftData
import SwiftUI

/// Settings (spec §24.2). Pushed inside the More tab's NavigationStack, so it must not create its own.
/// Later phases add Face ID, AI toggles, backup/restore, export, and appearance here.
struct SettingsView: View {
    @Environment(\.services) private var services
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("settings.categories")
                NavigationLink {
                    DataView()
                } label: {
                    Label("Backup and export", systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings.data")
                NavigationLink {
                    IntelligenceView()
                } label: {
                    Label("Intelligence", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.intelligence")
            }
            if let current = settings.first {
                Section("Household") {
                    LabeledContent("Currency", value: current.currencyCode)
                    LabeledContent("Starting balance") {
                        Text(startingBalance(current).formatted())
                    }
                    LabeledContent("As of") {
                        Text(current.startingBalanceDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                Section {
                    Toggle("Show amounts in widget", isOn: widgetShowsBalance(current))
                        .accessibilityIdentifier("settings.widgetShowsBalance")
                } header: {
                    Text("Widget")
                } footer: {
                    Text("When off, the Home Screen widget shows “Hidden” instead of your balances.")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func widgetShowsBalance(_ current: AppSettings) -> Binding<Bool> {
        Binding(
            get: { current.widgetShowsBalance },
            set: { value in
                Task {
                    try? await services?.transactions.setWidgetShowsBalance(value, now: .now)
                    await WidgetSync.refresh(services)
                }
            })
    }

    private func startingBalance(_ settings: AppSettings) -> Money {
        Money(minorUnits: settings.startingBalanceMinorUnits, currencyCode: settings.currencyCode)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
