import HouseholdHubCore
import SwiftData
import SwiftUI

/// Settings › Intelligence (spec §7.11, §12): each on-device AI feature has its own switch, off by default
/// (Sprint 7 default 1). Everything runs on this device; nothing is sent anywhere, and every feature has a non-AI
/// path.
struct IntelligenceView: View {
    @Environment(\.services) private var services
    @Query(sort: \AppSettings.createdAt) private var settings: [AppSettings]

    private var available: Bool { OnDeviceModel.isAvailable }

    var body: some View {
        List {
            Section {
                toggle("Quick Add understanding", feature: .naturalLanguage, value: \.naturalLanguageEnabled)
                toggle("Category suggestions", feature: .categorization, value: \.aiCategorizationEnabled)
                toggle("Analytics summaries", feature: .insights, value: \.aiInsightsEnabled)
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Intelligence")
    }

    private var footer: String {
        if available {
            return String(localized: "Uses Apple Intelligence on this device only. You check every suggestion.")
        }
        return String(
            localized: "Apple Intelligence isn't available on this device. Quick Add and categories work without it.")
    }

    private func toggle(
        _ title: LocalizedStringKey, feature: TransactionService.AISwitch, value: KeyPath<AppSettings, Bool>
    ) -> some View {
        Toggle(title, isOn: binding(feature, value))
            .disabled(!available || settings.isEmpty)
    }

    private func binding(_ feature: TransactionService.AISwitch, _ value: KeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.first?[keyPath: value] ?? false },
            set: { enabled in
                Task { try? await services?.transactions.setAI(feature, enabled: enabled, now: .now) }
            })
    }
}
