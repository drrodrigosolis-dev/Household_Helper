import XCTest

final class RecurringUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateSeriesThenPostItsNextOccurrence() {
        let app = launchApp()
        app.tabBars.buttons["Budget"].tap()
        app.buttons["Recurring"].tap()
        createRent(app)

        let row = recurringRow(app, containing: "Rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New series missing from Recurring")
        row.swipeLeft()
        app.buttons["Post"].tap()

        app.buttons["Transactions"].tap()
        XCTAssertTrue(transactionRow(app, containing: "Rent").waitForExistence(timeout: 10), "Posted rent missing")
    }

    @MainActor
    private func createRent(_ app: XCUIApplication) {
        let add = app.buttons["recurring.addEmpty"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let name = app.textFields["recurringEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rent")
        let amount = app.textFields["recurringEditor.amount"]
        amount.tap()
        amount.typeText("1200")
        app.buttons["recurringEditor.save"].tap()
    }

    @MainActor
    private func recurringRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "recurring.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
