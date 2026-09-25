import Testing

@testable import HouseholdHub

struct SmokeTests {
    @Test func appDisplayNameIsStable() {
        #expect(AppInfo.displayName == "Household Hub")
    }
}
