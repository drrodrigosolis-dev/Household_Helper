import XCTest

final class AnalyticsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPostedSpendingShowsByCategoryAndOpensBudgetFiltered() {
        let app = launchApp()
        addViaQuickAdd(app, "47.50 coffee #dining")
        addViaQuickAdd(app, "+ 1200 paycheck")
        openAnalytics(app)
        XCTAssertTrue(waitForRow(app, identifier: "analytics.net", toRead: "1,152.50"), "Net = 1,200.00 − 47.50")
        let dining = app.buttons.matching(identifier: "analytics.category")
            .matching(NSPredicate(format: "label CONTAINS %@", "Dining")).firstMatch
        XCTAssertTrue(dining.waitForExistence(timeout: 10), "Dining missing from spending by category")
        XCTAssertTrue(dining.label.contains("47.50"), "Category row should show its total: '\(dining.label)'")
        dining.tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5), "Tapping a category opens Budget")
        XCTAssertTrue(transactionRow(app, containing: "coffee").waitForExistence(timeout: 5))
        XCTAssertFalse(transactionRow(app, containing: "paycheck").exists, "Budget should be filtered to Dining")
    }
}

extension XCTestCase {
    @MainActor
    func openAnalytics(_ app: XCUIApplication) {
        app.tabBars.buttons["More"].tap()
        // The More tab keeps its navigation stack (the walk leaves it in Settings); step back to its root first.
        let analytics = app.buttons["Analytics"]
        let back = app.navigationBars.buttons["BackButton"]
        for _ in 0..<5 where !analytics.exists && back.exists {
            back.tap()
        }
        analytics.tap()
        XCTAssertTrue(app.navigationBars["Analytics"].waitForExistence(timeout: 5), "Analytics did not open")
    }
}
