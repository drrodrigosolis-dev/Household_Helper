import XCTest

/// Sprint 23: Select mode with bulk Set category and Delete (A-007), the Uncategorized filter (A-006), the editor's
/// Save waiting for a change (A-015), and where the floating + shows (A-013, A-014).
final class Sprint23ListUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBulkSetCategoryFilesEverySelectedRow() {
        let app = launchApp()
        addViaQuickAdd(app, "5 pens")
        addViaQuickAdd(app, "7 tape")
        app.tabBars.buttons["Budget"].tap()
        selectRows(app, ["pens", "tape"])

        let setCategory = app.buttons["transactions.bulkCategory"]
        XCTAssertTrue(setCategory.isEnabled, "Set category… needs a selection")
        setCategory.tap()
        let shopping = categoryOption(app, "Shopping")
        XCTAssertTrue(shopping.waitForExistence(timeout: 5), "The picker should offer the expense categories")
        XCTAssertFalse(categoryOption(app, "Salary").exists, "An income category can't file expenses")
        captureScreen(app, named: "sprint23-bulk-category-light")
        shopping.tap()

        for text in ["pens", "tape"] {
            let row = app.descendants(matching: .any).matching(identifier: "transaction.row")
                .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", text, "Shopping")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "'\(text)' should now be filed under Shopping")
        }
        XCTAssertFalse(app.buttons["transactions.bulkDelete"].exists, "A full success leaves Select mode")
    }

    @MainActor
    func testBulkDeleteIsConfirmedWithTheCountThenRemovesTheRows() {
        let app = launchApp()
        addViaQuickAdd(app, "5 pens")
        addViaQuickAdd(app, "7 tape")
        addViaQuickAdd(app, "9 glue")
        app.tabBars.buttons["Budget"].tap()
        selectRows(app, ["pens", "tape"])

        app.buttons["transactions.bulkDelete"].tap()
        let confirm = app.buttons["Delete 2 transactions"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Bulk delete must be confirmed, naming the count")
        captureScreen(app, named: "sprint23-bulk-delete-light")
        confirm.tap()

        XCTAssertTrue(transactionRow(app, containing: "pens").waitForNonExistence(timeout: 10))
        XCTAssertTrue(transactionRow(app, containing: "tape").waitForNonExistence(timeout: 10))
        XCTAssertTrue(transactionRow(app, containing: "glue").exists, "Unselected rows stay")
    }

    @MainActor
    func testUncategorizedFilterShowsOnlyRowsWithoutACategory() {
        let app = launchApp()
        addViaQuickAdd(app, "12 coffee #dining")
        addViaQuickAdd(app, "5 pens")
        app.tabBars.buttons["Budget"].tap()
        let coffee = transactionRow(app, containing: "coffee")
        let pens = transactionRow(app, containing: "pens")
        XCTAssertTrue(coffee.waitForExistence(timeout: 10), "Categorized expense missing from Budget")
        XCTAssertTrue(pens.waitForExistence(timeout: 10), "Uncategorized expense missing from Budget")

        let filter = app.buttons["budget.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "Budget has no filter menu")
        filter.tap()
        // A picker inside a menu lists its options inline; if this OS nests it instead, open the Category submenu.
        let uncategorized = app.buttons["Uncategorized"].firstMatch
        if !uncategorized.waitForExistence(timeout: 3) {
            app.buttons["Category"].firstMatch.tap()
        }
        XCTAssertTrue(uncategorized.waitForExistence(timeout: 5), "The filter menu should offer Uncategorized")
        uncategorized.tap()

        XCTAssertTrue(pens.waitForExistence(timeout: 10), "The uncategorized expense stays listed")
        XCTAssertTrue(coffee.waitForNonExistence(timeout: 10), "The Dining expense is filtered out")
        captureScreen(app, named: "sprint23-uncategorized-light")
    }

    @MainActor
    func testEditorSaveWaitsForAChange() {
        let app = launchApp()
        addViaQuickAdd(app, "20 lunch")
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: "lunch")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let amount = app.textFields["editor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Transaction editor did not open")
        let save = app.buttons["editor.save"]
        XCTAssertFalse(save.isEnabled, "Nothing changed yet, so Save is off")

        replaceText(in: amount, with: "25")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed, "An edit turns Save on")
        replaceText(in: amount, with: "20")
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [disabled], timeout: 5), .completed, "Undoing the edit turns Save off")

        replaceText(in: amount, with: "25")
        tapSaveAndWaitForClose(save, closes: amount)
        XCTAssertTrue(transactionRow(app, containing: "25.00").waitForExistence(timeout: 10))
    }

    @MainActor
    func testQuickAddButtonHidesWhileSearchingAndOnRecurringAndBudgets() {
        let app = launchApp()
        addViaQuickAdd(app, "5 pens")
        app.tabBars.buttons["Budget"].tap()
        let quickAdd = app.buttons["quickadd.button"]
        XCTAssertTrue(transactionRow(app, containing: "pens").waitForExistence(timeout: 10))
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5), "Transactions shows the floating +")

        app.buttons["Recurring"].tap()
        XCTAssertTrue(quickAdd.waitForNonExistence(timeout: 5), "Recurring has its own +")
        app.buttons["Budgets"].tap()
        XCTAssertTrue(quickAdd.waitForNonExistence(timeout: 5), "Budgets has its own +")
        app.buttons["Transactions"].tap()
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 5), "Transactions shows the floating + again")

        let search = searchField(app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Budget should offer search")
        search.tap()
        search.typeText("pens")
        XCTAssertTrue(transactionRow(app, containing: "pens").waitForExistence(timeout: 5), "Search finds the row")
        XCTAssertFalse(quickAdd.exists, "The floating + would cover search results")
        captureScreen(app, named: "sprint23-search-no-fab-light")
    }

    // MARK: Helpers

    /// Turns on Select mode and selects the rows naming each text, waiting for the count to read back.
    @MainActor
    private func selectRows(_ app: XCUIApplication, _ texts: [String]) {
        for text in texts {
            XCTAssertTrue(transactionRow(app, containing: text).waitForExistence(timeout: 10), "'\(text)' missing")
        }
        let select = app.buttons["transactions.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), "Transactions should offer Select")
        select.tap()
        XCTAssertTrue(app.buttons["transactions.bulkDelete"].waitForExistence(timeout: 5), "Select mode did not start")
        for text in texts {
            transactionRow(app, containing: text).tap()
        }
        let count = app.staticTexts["transactions.selectedCount"]
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "\(texts.count) ")
        let counted = XCTNSPredicateExpectation(predicate: predicate, object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [counted], timeout: 5), .completed, "Selection reads '\(count.label)'")
    }

    @MainActor
    private func categoryOption(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "transactions.bulkCategoryOption")
            .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    /// The search field; on some layouts it sits behind a Search button first.
    @MainActor
    private func searchField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) {
            let button = app.buttons["Search"].firstMatch
            if button.exists {
                button.tap()
            }
        }
        return field
    }
}
