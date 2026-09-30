import XCTest

/// Sprint 23: Undo after a delete (F3), and Budget's amount filter and saved searches (F6).
final class Sprint23UndoUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDeleteThenUndoBringsTheRowBack() {
        let app = launchApp()
        addViaQuickAdd(app, "12 parking")
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: "parking")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let delete = app.buttons["Delete"].firstMatch
        revealSwipeAction(row, delete)
        delete.tap()
        let confirm = app.buttons["Delete transaction"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete must be confirmed (spec §8.3)")
        confirm.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "The row goes at once")

        let undo = app.buttons["undo.button"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "A delete offers Undo")
        captureScreen(app, named: "sprint23-undo-banner-light")
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Undo brings the transaction back")
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "Undo is used once")
    }

    @MainActor
    func testBulkDeleteThenUndoBringsEveryRowBack() {
        let app = launchApp()
        addViaQuickAdd(app, "5 pens")
        addViaQuickAdd(app, "7 tape")
        app.tabBars.buttons["Budget"].tap()
        for text in ["pens", "tape"] {
            XCTAssertTrue(transactionRow(app, containing: text).waitForExistence(timeout: 10), "'\(text)' missing")
        }
        app.buttons["transactions.select"].tap()
        XCTAssertTrue(app.buttons["transactions.bulkDelete"].waitForExistence(timeout: 5), "Select mode did not start")
        for text in ["pens", "tape"] {
            transactionRow(app, containing: text).tap()
        }
        app.buttons["transactions.bulkDelete"].tap()
        let confirm = app.buttons["Delete 2 transactions"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Bulk delete must be confirmed, naming the count")
        confirm.tap()
        XCTAssertTrue(transactionRow(app, containing: "pens").waitForNonExistence(timeout: 10))
        XCTAssertTrue(transactionRow(app, containing: "tape").waitForNonExistence(timeout: 10))

        let banner = app.descendants(matching: .any)["undo.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "A bulk delete offers Undo")
        app.buttons["undo.button"].tap()
        for text in ["pens", "tape"] {
            XCTAssertTrue(transactionRow(app, containing: text).waitForExistence(timeout: 10), "'\(text)' is back")
        }
    }

    @MainActor
    func testAmountRangeFilterHidesSmallerAmounts() {
        let app = launchApp()
        addViaQuickAdd(app, "5 pens")
        addViaQuickAdd(app, "25 lamp")
        app.tabBars.buttons["Budget"].tap()
        let pens = transactionRow(app, containing: "pens")
        let lamp = transactionRow(app, containing: "lamp")
        XCTAssertTrue(pens.waitForExistence(timeout: 10))
        XCTAssertTrue(lamp.waitForExistence(timeout: 10))

        setMinimumAmount(app, "10")
        XCTAssertTrue(pens.waitForNonExistence(timeout: 10), "5.00 is under the minimum")
        XCTAssertTrue(lamp.exists, "25.00 is over it")
        captureScreen(app, named: "sprint23-amount-filter-light")
    }

    @MainActor
    func testSavedSearchReappliesItsFilter() {
        let app = launchApp()
        addViaQuickAdd(app, "5 pens")
        addViaQuickAdd(app, "25 lamp")
        app.tabBars.buttons["Budget"].tap()
        let pens = transactionRow(app, containing: "pens")
        let lamp = transactionRow(app, containing: "lamp")
        XCTAssertTrue(pens.waitForExistence(timeout: 10))
        XCTAssertTrue(lamp.waitForExistence(timeout: 10))
        setMinimumAmount(app, "10")
        XCTAssertTrue(pens.waitForNonExistence(timeout: 10))

        openFilterMenu(app)
        let save = app.buttons["Save search…"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "An active filter can be saved")
        save.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Saving asks for a name")
        name.tap()
        name.typeText("Big buys")
        app.alerts.buttons["Save"].tap()

        // Back to every amount, then the saved search narrows the list again.
        setMinimumAmount(app, "")
        XCTAssertTrue(pens.waitForExistence(timeout: 10), "Without the minimum every amount shows")
        openFilterMenu(app)
        let saved = app.buttons["Big buys"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "The saved search heads the filter menu")
        captureScreen(app, named: "sprint23-saved-search-light")
        saved.tap()
        XCTAssertTrue(pens.waitForNonExistence(timeout: 10), "The saved search brings its minimum back")
        XCTAssertTrue(lamp.exists)
    }

    // MARK: Helpers

    @MainActor
    private func openFilterMenu(_ app: XCUIApplication) {
        let filter = app.buttons["budget.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "Budget has no filter menu")
        filter.tap()
    }

    /// Opens More filters, sets (or, with "", clears) the minimum amount, and applies it.
    @MainActor
    private func setMinimumAmount(_ app: XCUIApplication, _ text: String) {
        openFilterMenu(app)
        let more = app.buttons["More filters…"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "The filter menu should offer More filters…")
        more.tap()
        let minimum = app.textFields["filter.minimumAmount"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 5), "More filters did not open")
        let placeholder = minimum.placeholderValue ?? ""
        if text.isEmpty {
            // Cleared, then checked like `replaceText`: one more try only if the field still holds text (run
            // 36453971771: the deletes were typed but Apply stayed off).
            for _ in 0..<2 {
                let value = (minimum.value as? String) ?? ""
                guard !value.isEmpty, value != placeholder else { break }
                minimum.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
                minimum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
                let cleared = NSPredicate(format: "value == '' OR value == %@", placeholder)
                _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: cleared, object: minimum)], timeout: 5)
            }
        } else {
            replaceText(in: minimum, with: text)
        }
        let apply = app.buttons["filter.apply"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: apply)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed, "Apply stayed off")
        apply.tap()
        XCTAssertTrue(minimum.waitForNonExistence(timeout: 5), "Apply closes More filters")
    }
}
