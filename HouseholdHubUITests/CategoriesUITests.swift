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
        // The new row is last, right above the floating tab bar; scroll it clear before swiping so the swipe
        // lands on the row and the revealed actions are tappable.
        app.swipeUp()
        row.swipeLeft()
        let archive = app.buttons["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5), "Swipe should reveal Archive")
        archive.tap()
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5), "Archived section should appear")
    }
}
