import XCTest

final class CategoriesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddThenArchiveACategory() {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()
        app.buttons["Settings"].tap()
        app.buttons["settings.categories"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))

        app.buttons["categories.add"].tap()
        let name = app.textFields["categoryEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Coffee")
        app.buttons["categoryEditor.save"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "category.row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Coffee")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New category missing")
        // The new row is last, just above the floating tab bar, where swipe-action taps are unreliable on a slow
        // simulator (runs 36202442661 and 36211055316). The row's context menu offers the same action in its own
        // layer, clear of the tab bar.
        row.press(forDuration: 1.0)
        let archive = app.buttons["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5), "The context menu should offer Archive")
        archive.tap()
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5), "Archived section should appear")
    }

    /// Spec §8.4: a category in use is never simply deleted. Deleting it offers to move its transactions first;
    /// "Move to … and delete" reassigns them and removes the category, and the transaction keeps its history.
    @MainActor
    func testDeletingACategoryInUseMovesItsTransactionsFirst() {
        let app = launchApp()
        openSettings(app)
        app.buttons["settings.categories"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        app.buttons["categories.add"].tap()
        let name = app.textFields["categoryEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Coffee")
        app.buttons["categoryEditor.save"].tap()
        let row = categoryRow(app, containing: "Coffee")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New category missing")

        // Back to the More root, which has the Quick Add button; the #coffee tag files the expense under Coffee.
        app.navigationBars.buttons["Settings"].tap()
        app.navigationBars.buttons["More"].tap()
        addViaQuickAdd(app, "4 latte #coffee")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["settings.categories"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Category missing after Quick Add")

        // The context menu, not the swipe: the new row sits just above the tab bar (see testAddThenArchiveACategory).
        row.press(forDuration: 1.0)
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "A custom category's menu should offer Delete")
        delete.tap()
        let confirm = app.buttons["Delete Coffee"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Deleting must be confirmed")
        confirm.tap()
        let move = app.buttons["Move to Dining and delete"]
        XCTAssertTrue(move.waitForExistence(timeout: 10), "A category in use should offer moving its items")
        move.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "The category should be deleted after the move")
        XCTAssertFalse(app.staticTexts["Archived"].exists, "Moving deletes the category; it is not archived")

        app.tabBars.buttons["Budget"].tap()
        let latte = transactionRow(app, containing: "latte")
        XCTAssertTrue(latte.waitForExistence(timeout: 10), "The transaction must survive the category delete")
        XCTAssertTrue(latte.label.contains("Dining"), "The transaction should now be in Dining: '\(latte.label)'")
    }

    @MainActor
    private func categoryRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "category.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
