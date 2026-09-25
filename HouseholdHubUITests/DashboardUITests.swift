import XCTest

final class DashboardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDashboardReflectsNewExpenseAndDeepLinksIntoBudget() {
        let app = launchApp()
        addViaQuickAdd(app, "47.50 coffee")
        app.tabBars.buttons["Dashboard"].tap()
        let amount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "47.50")).firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Current balance did not update after Quick Add")

        app.buttons["dashboard.pending"].tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5), "Pending card should open Budget")
    }

    @MainActor
    func testProjectedCardOpensRecurring() {
        let app = launchApp()
        let projected = app.buttons["dashboard.projected"]
        XCTAssertTrue(projected.waitForExistence(timeout: 10))
        projected.tap()
        XCTAssertTrue(app.buttons["recurring.addEmpty"].waitForExistence(timeout: 5))
    }
}
