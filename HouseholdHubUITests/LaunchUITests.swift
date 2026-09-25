import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
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
