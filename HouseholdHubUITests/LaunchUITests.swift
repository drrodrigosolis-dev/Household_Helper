import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEachPrimaryTabShowsItsScreen() {
        let app = launchApp()
        for tab in ["Dashboard", "Budget", "Wishlist", "Tasks", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab button '\(tab)' missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5), "'\(tab)' screen did not appear")
        }
    }

    @MainActor
    func testMoreReachesAnalytics() {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()
        app.buttons["Analytics"].tap()
        XCTAssertTrue(app.navigationBars["Analytics"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoreReachesSettings() {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}

/// Phase 10 performance: cold-launch time into the Dashboard (spec NFR). Recorded in the result bundle; CI's shared
/// simulator is too noisy for a hard threshold, so the owner sets a baseline on the Mac (WALK-QUEUE).
final class LaunchPerformanceUITests: XCTestCase {
    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-uiTestingSkipOnboarding"]
            app.launch()
        }
    }
}
