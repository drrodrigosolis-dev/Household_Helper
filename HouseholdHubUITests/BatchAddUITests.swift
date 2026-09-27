import XCTest

/// Sprint 17: Add several. A pasted list is previewed line by line, then added with one save.
final class BatchAddUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPastedTasksArePreviewedAndAddedToTheBoard() {
        let app = launchApp()
        let editor = openBatchAdd(app, tab: "Tasks", button: "tasks.addSeveral")
        typeList(editor, "- buy 2 lightbulbs\n- call plumber friday\n\n- renew passport")
        XCTAssertTrue(waitForCount(app, 3), "Preview should list 3 tasks to add")
        captureScreen(app, named: "sprint17-batch-tasks-light")
        saveBatch(app, editor)
        for title in ["buy 2 lightbulbs", "call plumber", "renew passport"] {
            let card = taskCard(app, containing: title)
            XCTAssertTrue(card.waitForExistence(timeout: 10), "'\(title)' not on the board")
        }
        XCTAssertFalse(taskCard(app, containing: "friday").exists, "The day word becomes the due date, not the title")
        captureScreen(app, named: "sprint17-batch-tasks-board-light")
    }

    @MainActor
    func testPastedWishlistItemsAreAddedWithPricesInDark() {
        let app = launchApp(variant: .dark)
        let editor = openBatchAdd(app, tab: "Wishlist", button: "wishlist.addSeveral")
        typeList(editor, "250 new bike\nheadphones\n$1,200 sofa\n99")
        XCTAssertTrue(waitForCount(app, 3), "Preview should add 3 items and skip the bare number")
        captureScreen(app, named: "sprint17-batch-wishlist-dark")
        saveBatch(app, editor)
        for name in ["new bike", "headphones", "sofa"] {
            XCTAssertTrue(wishlistRow(app, containing: name).waitForExistence(timeout: 10), "'\(name)' not listed")
        }
        captureScreen(app, named: "sprint17-batch-wishlist-list-dark")
    }

    @MainActor
    func testPreviewAtTheLargestTextSize() {
        let app = launchApp(variant: .largeText)
        let editor = openBatchAdd(app, tab: "Tasks", button: "tasks.addSeveral")
        typeList(editor, "water plants tomorrow\nbook dentist")
        XCTAssertTrue(waitForCount(app, 2), "Preview should list 2 tasks to add")
        captureScreen(app, named: "sprint17-batch-tasks-largeText")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(taskCard(app, containing: "book dentist").waitForExistence(timeout: 2), "Cancel adds nothing")
    }

    // MARK: Helpers

    @MainActor
    private func openBatchAdd(_ app: XCUIApplication, tab: String, button: String) -> XCUIElement {
        let tabButton = app.tabBars.buttons[tab]
        XCTAssertTrue(tabButton.waitForExistence(timeout: 30), "Tab bar never appeared")
        tabButton.tap()
        let open = app.buttons[button]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "\(tab) has no Add several button")
        open.tap()
        let editor = app.textViews["batch.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Add several did not open")
        return editor
    }

    @MainActor
    private func typeList(_ editor: XCUIElement, _ text: String) {
        editor.tap()
        editor.typeText(text)
    }

    /// Waits for the preview header to count `count` lines to add. Keystrokes can reach the app after `typeText`
    /// returns (run 36326496000), so the count is read, not assumed.
    @MainActor
    private func waitForCount(_ app: XCUIApplication, _ count: Int) -> Bool {
        let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "· \(count) to add"))
            .firstMatch
        return header.waitForExistence(timeout: 10)
    }

    @MainActor
    private func saveBatch(_ app: XCUIApplication, _ editor: XCUIElement) {
        let save = app.buttons["batch.save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, "Add stayed disabled")
        save.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Add several did not close")
    }
}
