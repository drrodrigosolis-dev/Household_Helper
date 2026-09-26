import Foundation
import HouseholdHubCore

enum AppInfo {
    static let displayName = "Household Hub"
    /// Written into backups (spec §26 `appVersion`).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    /// The App Group shared with the widget, when one is configured (spec §5.2); nil under the free Personal Team.
    static var appGroupIdentifier: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String
        return value?.isEmpty == false ? value : nil
    }
}

enum LaunchArguments {
    /// UI tests launch with this so they run against an empty in-memory store, never the user's data.
    static let uiTesting = "-uiTesting"
    /// UI tests that are not about onboarding start from a completed setup (CAD, zero balance).
    static let skipOnboarding = "-uiTestingSkipOnboarding"
    /// Screenshot walk: render in dark mode. The simulator ignores XCUIDevice appearance changes during a run.
    static let darkMode = "-uiTestingDarkMode"
}
