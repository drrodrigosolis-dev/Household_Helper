import XCTest

final class BudgetUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testQuickAddExpenseAppearsInBudgetWithItsSign() {
        let app = launchApp()
        addViaQuickAdd(app, "47.50 coffee")
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: "coffee")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New expense missing from Budget")
        XCTAssertTrue(row.label.contains("47.50"), "Row label '\(row.label)' lacks the amount")
        XCTAssertTrue(row.label.contains("-"), "Expense should read as negative: '\(row.label)'")
    }

    @MainActor
    func testQuickAddIncomeIsRecordedAsIncome() {
        let app = launchApp()
        addViaQuickAdd(app, "+ 1200 paycheck")
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: "paycheck")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("+"), "Income should read as positive: '\(row.label)'")
    }

    @MainActor
    func testSaveStaysDisabledWithoutAnAmount() {
        let app = launchApp()
        app.buttons["quickadd.button"].tap()
        let field = app.textFields["quickadd.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("coffee")
        XCTAssertFalse(app.buttons["quickadd.save"].isEnabled)
    }

    @MainActor
    func testSwipeDeleteAsksForConfirmationThenRemovesTheRow() {
        let app = launchApp()
        addViaQuickAdd(app, "12 parking")
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: "parking")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let confirm = app.buttons["Delete transaction"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete must be confirmed (spec §8.3)")
        confirm.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed)
    }

    @MainActor
    func testEditChangesTheAmount() {
        let app = launchApp()
        addViaQuickAdd(app, "20 lunch")
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: "lunch")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let amount = app.textFields["editor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replaceText(in: amount, with: "25")
        captureScreen(app, named: "light-TransactionEditor")
        app.buttons["editor.save"].tap()
        let edited = transactionRow(app, containing: "25.00")
        XCTAssertTrue(edited.waitForExistence(timeout: 10), "Edited amount not shown in the list")
    }
}
