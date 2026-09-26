import HouseholdHubCore
import SwiftData
import SwiftUI

/// Settings (spec §24.2). Pushed inside the More tab's NavigationStack, so it must not create its own.
/// Later phases add Face ID, AI toggles, backup/restore, export, and appearance here.
struct SettingsView: View {
    @Environment(\.services) private var services
    @Environment(\.self) private var environment
    /// The pending custom-accent save: dragging in the color picker sends many values, and only the last is kept.
    @State private var accentWrite: Task<Void, Never>?
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
                        if let custom = settings.first?.accentColor, !CategoryEditorView.palette.contains(custom) {
                            Text("Custom").tag(ColorToken?.some(custom))
                        }
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
                    ColorPicker("Custom accent", selection: customAccentBinding, supportsOpacity: false)
                        .accessibilityIdentifier("settings.customAccent")
                    if let warning = accentWarning {
                        Text(warning).font(.footnote).foregroundStyle(.secondary)
                    }
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
                    Household Hub keeps your data on this device. Nothing is sent anywhere. Apple Intelligence \
                    features run on this device only, and each can be turned off in Intelligence.
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

    /// Any color (owner decision 2026-09-26), stored as an opaque sRGB token.
    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { settings.first?.accentColor.map { Color($0) } ?? .accentColor },
            set: { color in
                let token = ColorToken(color.resolve(in: environment))
                let theme = settings.first?.selectedTheme ?? .system
                accentWrite?.cancel()
                accentWrite = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    try? await services?.transactions.setAppearance(theme: theme, accent: token, now: .now)
                }
            })
    }

    /// Buttons and links take the accent color, so a choice below 3:1 against the list background gets a warning.
    private var accentWarning: String? {
        switch settings.first?.accentColor?.accentVisibility ?? .fine {
        case .fine: return nil
        case .hardInLightMode: return String(localized: "This color is hard to see in Light Mode.")
        case .hardInDarkMode: return String(localized: "This color is hard to see in Dark Mode.")
        }
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
