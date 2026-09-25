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
        row.swipeLeft()
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5), "Archived section should appear")
    }
}
