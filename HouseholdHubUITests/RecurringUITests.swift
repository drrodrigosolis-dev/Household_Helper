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
        let post = app.buttons["Post"]
        revealSwipeAction(row, post)
        post.tap()

        app.buttons["Transactions"].tap()
        XCTAssertTrue(transactionRow(app, containing: "Rent").waitForExistence(timeout: 10), "Posted rent missing")
    }

    /// v1 audit: a series can be edited (its row shows the new amount) and, with nothing posted, deleted.
    @MainActor
    func testEditSeriesThenDeleteIt() {
        let app = launchApp()
        app.tabBars.buttons["Budget"].tap()
        app.buttons["Recurring"].tap()
        createRent(app)

        let row = recurringRow(app, containing: "Rent")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New series missing from Recurring")
        let edit = app.buttons["Edit"]
        XCTAssertTrue(revealSwipeAction(row, edit, leading: true), "Leading swipe should offer Edit")
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Recurring Item"].waitForExistence(timeout: 5), "Editor did not open")
        replaceText(in: app.textFields["recurringEditor.amount"], with: "1350")
        tapSaveAndWaitForClose(app.buttons["recurringEditor.save"], closes: app.navigationBars["Edit Recurring Item"])
        let edited = recurringRow(app, containing: "1,350.00")
        XCTAssertTrue(edited.waitForExistence(timeout: 10), "The row should show the edited amount")

        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(revealSwipeAction(edited, delete, leading: true), "Leading swipe should offer Delete")
        delete.tap()
        let confirm = app.sheets.buttons["Delete"].firstMatch
        let fallback = app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).element(boundBy: 0)
        let button = confirm.waitForExistence(timeout: 5) ? confirm : fallback
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Deleting should ask first")
        button.tap()
        XCTAssertTrue(app.buttons["recurring.addEmpty"].waitForExistence(timeout: 10), "The series should be gone")
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
