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

    /// Sprint 22: a recurring purchase names its store, shows a cart, and posts as an expense.
    @MainActor
    func testRecurringPurchaseNamesItsStore() {
        let app = launchApp()
        app.tabBars.buttons["Budget"].tap()
        app.buttons["Recurring"].tap()
        let add = app.buttons["recurring.addEmpty"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let kind = app.segmentedControls["recurringEditor.kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5), "The editor should offer Bill or Purchase")
        kind.buttons["Purchase"].tap()
        XCTAssertFalse(app.segmentedControls["recurringEditor.type"].exists, "A purchase is always an expense")
        let name = app.textFields["recurringEditor.name"]
        name.tap()
        name.typeText("Groceries")
        let store = app.textFields["recurringEditor.store"]
        XCTAssertTrue(store.waitForExistence(timeout: 5), "A purchase names its store")
        store.tap()
        store.typeText("Corner Market")
        let amount = app.textFields["recurringEditor.amount"]
        amount.tap()
        amount.typeText("80")
        captureScreen(app, named: "sprint22-recurring-purchase-editor-light")
        tapSaveAndWaitForClose(app.buttons["recurringEditor.save"], closes: store)

        XCTAssertTrue(recurringRow(app, containing: "Corner Market").waitForExistence(timeout: 10), "No store")
        captureScreen(app, named: "sprint22-recurring-list-light")

        // Editing keeps it a purchase at its store (data-safety review B2a).
        let edit = app.buttons["Edit"]
        XCTAssertTrue(revealSwipeAction(recurringRow(app, containing: "Corner Market"), edit, leading: true))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Recurring Item"].waitForExistence(timeout: 5), "Editor did not open")
        XCTAssertTrue(app.segmentedControls["recurringEditor.kind"].buttons["Purchase"].isSelected, "Still a purchase")
        XCTAssertEqual(app.textFields["recurringEditor.store"].value as? String, "Corner Market")
        replaceText(in: app.textFields["recurringEditor.amount"], with: "85")
        tapSaveAndWaitForClose(app.buttons["recurringEditor.save"], closes: app.navigationBars["Edit Recurring Item"])
        let row = recurringRow(app, containing: "85.00")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The edit should show the new amount")
        XCTAssertTrue(row.label.contains("Corner Market"), "The edit kept the store: \(row.label)")

        let post = app.buttons["Post"]
        revealSwipeAction(row, post)
        post.tap()
        app.buttons["Transactions"].tap()
        // A posted purchase is named by its store (Sprint 22 decision 1).
        let posted = transactionRow(app, containing: "Corner Market")
        XCTAssertTrue(posted.waitForExistence(timeout: 10), "Posted purchase missing")
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
