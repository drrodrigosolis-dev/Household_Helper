enum AppInfo {
    static let displayName = "Household Hub"
}

enum LaunchArguments {
    /// UI tests launch with this so they run against an empty in-memory store, never the user's data.
    static let uiTesting = "-uiTesting"
    /// UI tests that are not about onboarding start from a completed setup (CAD, zero balance).
    static let skipOnboarding = "-uiTestingSkipOnboarding"
}
