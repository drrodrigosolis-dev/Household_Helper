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
        addViaQuickAdd(app, "47.50 coffee")
        addViaQuickAdd(app, "+ 1200 paycheck")
        app.buttons["quickadd.button"].tap()
        let field = app.textFields["quickadd.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("32.10 groceries yesterday")
        captureScreen(app, named: "\(variant.rawValue)-QuickAdd")
        app.buttons["Cancel"].tap()
        for tab in ["Dashboard", "Budget", "Wishlist", "Tasks", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab button '\(tab)' missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
            captureScreen(app, named: "\(variant.rawValue)-\(tab)")
        }
        walkSecondaryScreens(app, variant)
    }

    /// Recurring, Settings and Categories, including their editors.
    @MainActor
    private func walkSecondaryScreens(_ app: XCUIApplication, _ variant: WalkVariant) {
        let prefix = variant.rawValue
        app.tabBars.buttons["Budget"].tap()
        app.buttons["Recurring"].tap()
        XCTAssertTrue(app.buttons["recurring.addEmpty"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Recurring-empty")
        app.buttons["recurring.addEmpty"].tap()
        XCTAssertTrue(app.textFields["recurringEditor.name"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-RecurringEditor")
        app.buttons["Cancel"].tap()
        app.buttons["Transactions"].tap()

        app.tabBars.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Settings")
        app.buttons["settings.categories"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Categories")
        app.buttons["categories.add"].tap()
        XCTAssertTrue(app.textFields["categoryEditor.name"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-CategoryEditor")
        app.buttons["Cancel"].tap()
    }
}
