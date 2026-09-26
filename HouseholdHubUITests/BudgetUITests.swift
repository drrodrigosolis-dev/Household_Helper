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
        let field = openQuickAdd(app)
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

    /// Spec §24.2: the filter menu narrows the list in the store. A category filter keeps only that category's rows;
    /// Clear filters brings the rest back.
    @MainActor
    func testCategoryFilterShowsOnlyMatchingTransactions() {
        let app = launchApp()
        addViaQuickAdd(app, "12 coffee #dining")
        addViaQuickAdd(app, "+ 500 paycheck #salary")
        app.tabBars.buttons["Budget"].tap()
        let coffee = transactionRow(app, containing: "coffee")
        let paycheck = transactionRow(app, containing: "paycheck")
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), "Expense missing from Budget")
        XCTAssertTrue(paycheck.waitForExistence(timeout: 10), "Income missing from Budget")

        let filter = app.buttons["budget.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "Budget has no filter menu")
        XCTAssertEqual(filter.value as? String, "Off")
        filter.tap()
        // A picker inside a menu lists its options inline; if this OS nests it instead, open the Category submenu.
        let dining = app.buttons["Dining"].firstMatch
        if !dining.waitForExistence(timeout: 3) {
            app.buttons["Category"].firstMatch.tap()
        }
        XCTAssertTrue(dining.waitForExistence(timeout: 5), "The filter menu should list the categories")
        dining.tap()

        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "On"), object: filter)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 5), .completed, "Filter should read as on")
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), "The Dining expense should stay listed")
        XCTAssertTrue(paycheck.waitForNonExistence(timeout: 10), "The Salary income should be filtered out")

        filter.tap()
        let clear = app.buttons["Clear filters"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "An active filter should offer Clear filters")
        clear.tap()
        XCTAssertTrue(paycheck.waitForExistence(timeout: 10), "Clearing the filter should list the income again")
        XCTAssertTrue(coffee.exists)
    }
}
