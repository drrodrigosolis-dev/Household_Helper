import XCTest

/// Sprint 23 (F4): Split… divides one payment into parts that add up to it exactly, Unsplit merges them back, and
/// Duplicate records the same payment again today.
final class Sprint23SplitUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSplittingAHundredIntoSixtyAndFortyThenUnsplitting() {
        let app = launchApp()
        addViaQuickAdd(app, "100 hardware")
        openTransaction(app, containing: "hardware")

        let split = app.buttons["editor.split"]
        XCTAssertTrue(scrollUntilExists(app, split), "Split… missing from the editor")
        split.tap()
        let amounts = app.textFields.matching(identifier: "split.row.amount")
        XCTAssertTrue(amounts.firstMatch.waitForExistence(timeout: 5), "Split sheet did not open")
        XCTAssertEqual(amounts.count, 2, "A split starts with two parts")
        let first = amounts.element(boundBy: 0)
        XCTAssertEqual(first.value as? String, "100.00", "Part 1 starts with the whole total")
        XCTAssertTrue(waitForRow(app, identifier: "split.remaining", toRead: "0.00"), "Part 1 holds all 100")
        let save = app.buttons["split.save"]
        XCTAssertFalse(save.isEnabled, "Part 2 has no amount yet")

        // Typing part 2 is enough: part 1 keeps what is left.
        replaceText(in: amounts.element(boundBy: 1), with: "40")
        let sixtyLeft = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "60.00"), object: first)
        XCTAssertEqual(XCTWaiter().wait(for: [sixtyLeft], timeout: 10), .completed, "Part 1 follows to 60")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, "60 + 40 adds up to 100")

        // Once typed in, part 1 keeps its amount and the check waits for the parts to add up again.
        replaceText(in: first, with: "70")
        XCTAssertTrue(waitForRow(app, identifier: "split.remaining", toRead: "10.00"), "70 + 40 is 10 over")
        XCTAssertFalse(save.isEnabled, "Save waits until the parts add up")
        replaceText(in: first, with: "60")
        let enabledAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [enabledAgain], timeout: 10), .completed, "60 + 40 again")
        XCTAssertTrue(app.buttons["split.add"].exists, "More parts can be added")
        captureScreen(app, named: "sprint23-split-sheet-light")
        tapSaveAndWaitForClose(save, closes: amounts.firstMatch)

        // The editor closes too: its record is now the first part.
        let editor = app.navigationBars["Transaction"]
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "The editor should close")
        let sixty = transactionRow(app, containing: "60.00")
        let forty = transactionRow(app, containing: "40.00")
        XCTAssertTrue(sixty.waitForExistence(timeout: 10), "The first part shows 60")
        XCTAssertTrue(forty.waitForExistence(timeout: 10), "The second part shows 40")
        XCTAssertFalse(transactionRow(app, containing: "100.00").exists, "The 100 became its parts")
        captureScreen(app, named: "sprint23-split-list-light")

        forty.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Editor did not open")
        let info = app.descendants(matching: .any)["editor.splitInfo"]
        XCTAssertTrue(scrollUntilExists(app, info), "A part says it belongs to a split")
        XCTAssertTrue(waitForRow(app, identifier: "editor.splitInfo", toRead: "2"), "Two parts")
        app.buttons["editor.unsplit"].tap()
        let confirm = app.buttons["editor.unsplit.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Unsplit asks first")
        confirm.tap()
        // A new expectation: each one can be waited on only once.
        let closedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter().wait(for: [closedAgain], timeout: 10), .completed, "Unsplit closes the editor")
        XCTAssertTrue(transactionRow(app, containing: "100.00").waitForExistence(timeout: 10), "One 100 again")
        XCTAssertFalse(transactionRow(app, containing: "40.00").exists, "The parts merged")
    }

    @MainActor
    func testDuplicateRecordsTheSamePaymentAgainToday() {
        let app = launchApp()
        addViaQuickAdd(app, "12 coffee")
        openTransaction(app, containing: "coffee")

        let duplicate = app.buttons["editor.duplicate"]
        XCTAssertTrue(scrollUntilExists(app, duplicate), "Duplicate missing from the editor")
        duplicate.tap()
        // The editor now shows the copy, saying so, so it can be adjusted.
        let notice = app.descendants(matching: .any)["editor.duplicated"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "Duplicate should open the copy and say so")
        let editor = app.navigationBars["Transaction"]
        XCTAssertTrue(editor.exists, "The copy opens in the editor")
        XCTAssertEqual(app.textFields["editor.amount"].value as? String, "12.00", "The copy has the original's amount")
        captureScreen(app, named: "sprint23-duplicate-copy-light")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: editor)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "Back returns to the list")
        let rows = app.descendants(matching: .any).matching(identifier: "transaction.row")
            .matching(NSPredicate(format: "label CONTAINS %@", "coffee"))
        XCTAssertTrue(rows.element(boundBy: 1).waitForExistence(timeout: 10), "The copy is its own row")
        XCTAssertEqual(rows.count, 2, "Exactly one copy")
        captureScreen(app, named: "sprint23-duplicate-list-light")
    }

    // MARK: Helpers

    @MainActor
    private func openTransaction(_ app: XCUIApplication, containing text: String) {
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: text)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "'\(text)' missing from Budget")
        row.tap()
        XCTAssertTrue(app.navigationBars["Transaction"].waitForExistence(timeout: 10), "Editor did not open")
    }
}
