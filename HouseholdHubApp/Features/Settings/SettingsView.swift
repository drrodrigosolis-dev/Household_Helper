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
                    Toggle("Require \(BiometricGate.methodName)", isOn: faceIDBinding)
                        .disabled(!BiometricGate.isAvailable && !current.faceIDEnabled)
                        .accessibilityIdentifier("settings.faceID")
                } header: {
                    Text("Privacy")
                } footer: {
                    if BiometricGate.isAvailable {
                        Text("Household Hub locks when you leave it. Your device passcode always works as a fallback.")
                    } else {
                        Text("Set a passcode on this device to lock Household Hub.")
                    }
                }
                Section("Appearance") {
                    Picker("Theme", selection: themeBinding) {
                        Text("System").tag(ThemePreference.system)
                        Text("Light").tag(ThemePreference.light)
                        Text("Dark").tag(ThemePreference.dark)
                    }
                    .accessibilityIdentifier("settings.theme")
                    Picker("Accent color", selection: accentBinding) {
                        Text("Default").tag(ColorToken?.none)
                        ForEach(CategoryEditorView.palette, id: \.self) { token in
                            Label {
                                Text(CategoryEditorView.colorName(token))
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color(token))
                            }
                            .tag(ColorToken?.some(token))
                        }
                    }
                    .accessibilityIdentifier("settings.accent")
                }
                Section("Quick Add") {
                    Picker("Opens on", selection: quickAddTypeBinding) {
                        Text("Expense").tag(QuickAddType.expense)
                        Text("Income").tag(QuickAddType.income)
                        Text("Wishlist").tag(QuickAddType.wishlist)
                        Text("Task").tag(QuickAddType.task)
                    }
                    .accessibilityIdentifier("settings.quickAddType")
                }
                Section {
                    Toggle("Show amounts in widget", isOn: widgetShowsBalanceBinding)
                        .accessibilityIdentifier("settings.widgetShowsBalance")
                } header: {
                    Text("Widget")
                } footer: {
                    Text("When off, the Home Screen widget shows “Hidden” instead of your balances.")
                }
            }
            Section("About") {
                LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                Text(
                    """
                    Household Hub keeps your data on this device. Nothing is sent anywhere, and on-device Apple \
                    Intelligence features are optional and off until you turn them on.
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    /// Turning the gate on asks for authentication first, so it can't be enabled on a device the owner can't unlock.
    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { settings.first?.faceIDEnabled ?? false },
            set: { value in
                Task {
                    if value {
                        let reason = String(localized: "Turn on the lock for Household Hub")
                        guard await BiometricGate.authenticate(reason: reason) else { return }
                    }
                    try? await services?.transactions.setFaceIDEnabled(value, now: .now)
                }
            })
    }

    private var themeBinding: Binding<ThemePreference> {
        Binding(
            get: { settings.first?.selectedTheme ?? .system },
            set: { value in
                let accent = settings.first?.accentColor
                Task { try? await services?.transactions.setAppearance(theme: value, accent: accent, now: .now) }
            })
    }

    private var accentBinding: Binding<ColorToken?> {
        Binding(
            get: { settings.first?.accentColor },
            set: { value in
                let theme = settings.first?.selectedTheme ?? .system
                Task { try? await services?.transactions.setAppearance(theme: theme, accent: value, now: .now) }
            })
    }

    private var quickAddTypeBinding: Binding<QuickAddType> {
        Binding(
            get: { settings.first?.defaultQuickAddType ?? .expense },
            set: { value in Task { try? await services?.transactions.setDefaultQuickAddType(value, now: .now) } })
    }

    private var widgetShowsBalanceBinding: Binding<Bool> {
        Binding(
            get: { settings.first?.widgetShowsBalance ?? true },
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
