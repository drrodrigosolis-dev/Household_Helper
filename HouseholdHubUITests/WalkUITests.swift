import XCTest

/// Screenshot walk of every primary screen in each presentation variant. Reviewed by eye before an item is ☑ walked.
final class WalkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkLight() {
        walkPrimaryScreens(.light)
    }

    @MainActor
    func testWalkDark() {
        walkPrimaryScreens(.dark)
    }

    @MainActor
    func testWalkLargeText() {
        walkPrimaryScreens(.largeText)
    }

    @MainActor
    private func walkPrimaryScreens(_ variant: WalkVariant) {
        let app = launchApp(variant: variant)
        for tab in ["Dashboard", "Budget", "Wishlist", "Tasks", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab button '\(tab)' missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
            captureScreen(app, named: "\(variant.rawValue)-\(tab)")
        }
    }
}
