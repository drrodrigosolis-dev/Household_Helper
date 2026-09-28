import XCTest

/// Sprint 23: Budgets' month history (A-017), Analytics categories and bars that open their transactions with the
/// change vs last month (A-018), and the "Last month" summary (F5).
final class Sprint23AnalyticsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testBudgetsStepBackAMonthAndForwardButNeverPastThisMonth() {
        let app = launchApp()
        addDiningBudget(app, limit: "300")
        XCTAssertTrue(budgetRow(app, containing: "300.00 left").waitForExistence(timeout: 10), "New budget missing")
        // The floating + isn't on Budgets (audit A-013): add from the Dashboard.
        app.tabBars.buttons["Dashboard"].tap()
        addViaQuickAdd(app, "45 lunch #dining")
        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(budgetRow(app, containing: "255.00 left").waitForExistence(timeout: 10))

        let previous = app.buttons["budgets.previousMonth"]
        let next = app.buttons["budgets.nextMonth"]
        let month = app.descendants(matching: .any)["budgets.month"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "Budgets should offer the previous month")
        XCTAssertFalse(next.isEnabled, "Never past the current month")
        let thisMonth = month.label

        previous.tap()
        XCTAssertTrue(
            month.waitForLabel(notEqualTo: thisMonth), "The month's name should change to the previous month")
        // The budget reads last month with its limit and last month's spending: nothing yet.
        XCTAssertTrue(budgetRow(app, containing: "300.00 left").waitForExistence(timeout: 10))
        XCTAssertFalse(budgetRow(app, containing: "255.00 left").exists, "This month's lunch isn't last month's")
        XCTAssertTrue(next.isEnabled, "Next goes back toward this month")
        captureScreen(app, named: "sprint23-budgets-previous-month-light")

        next.tap()
        XCTAssertTrue(month.waitForLabel(equalTo: thisMonth), "Next should return to this month")
        XCTAssertTrue(budgetRow(app, containing: "255.00 left").waitForExistence(timeout: 10))
        XCTAssertFalse(next.isEnabled)
    }

    @MainActor
    func testTappingACategoryOrABarOpensItsTransactions() {
        let app = launchApp()
        addViaQuickAdd(app, "47.50 coffee #dining")
        addViaQuickAdd(app, "5 pens")
        openAnalytics(app)

        // Uncategorized opens too now (Sprint 23), and each row says how it moved since last month.
        let uncategorized = app.buttons.matching(identifier: "analytics.category")
            .matching(NSPredicate(format: "label CONTAINS %@", "Uncategorized")).firstMatch
        XCTAssertTrue(scrollUntilExists(app, uncategorized), "Uncategorized missing from spending by category")
        XCTAssertTrue(
            uncategorized.label.contains("from last month"),
            "The row should read its change vs last month: '\(uncategorized.label)'")
        captureScreen(app, named: "sprint23-analytics-changes-light")
        uncategorized.tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5), "Tapping a category opens Budget")
        XCTAssertTrue(transactionRow(app, containing: "pens").waitForExistence(timeout: 10))
        XCTAssertTrue(
            transactionRow(app, containing: "coffee").waitForNonExistence(timeout: 10),
            "Budget should be filtered to transactions without a category")

        // A week's row (the non-gesture path to the bars) opens that week's transactions.
        openAnalytics(app)
        let week = app.buttons.matching(identifier: "analytics.trend")
            .matching(NSPredicate(format: "label CONTAINS %@", "52.50")).firstMatch
        XCTAssertTrue(scrollUntilExists(app, week, maxSwipes: 8), "This week's row should show 52.50 spent")
        week.tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5), "Tapping a week opens Budget")
        XCTAssertTrue(transactionRow(app, containing: "coffee").waitForExistence(timeout: 10))
        XCTAssertTrue(transactionRow(app, containing: "pens").waitForExistence(timeout: 10))
    }

    @MainActor
    func testLastMonthSummaryIsShown() {
        for variant in WalkVariant.allCases {
            let app = launchApp(variant: variant)
            openAnalytics(app)
            let summary = app.descendants(matching: .any)["analytics.monthSummary"]
            XCTAssertTrue(scrollUntilExists(app, summary, maxSwipes: 10), "Analytics should end with Last month")
            let nothing = app.staticTexts["Nothing was recorded last month."]
            XCTAssertTrue(scrollUntilExists(app, nothing), "A fresh install recorded nothing last month")
            captureScreen(app, named: "sprint23-analytics-last-month-\(variant.rawValue)")
            app.terminate()
        }
    }

    // MARK: Helpers

    @MainActor
    private func addDiningBudget(_ app: XCUIApplication, limit: String) {
        let budgetTab = app.tabBars.buttons["Budget"]
        XCTAssertTrue(budgetTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        budgetTab.tap()
        app.buttons["Budgets"].tap()
        let add = app.buttons["budgets.addEmpty"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Empty budgets should offer Add budget")
        add.tap()
        let picker = app.buttons["budgetEditor.category"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Budget editor did not open")
        picker.tap()
        let dining = app.buttons["Dining"].firstMatch
        XCTAssertTrue(dining.waitForExistence(timeout: 5), "Dining should be offered")
        dining.tap()
        let field = app.textFields["budgetEditor.limit"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(limit)
        app.buttons["budgetEditor.save"].tap()
    }

    @MainActor
    private func budgetRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "budget.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}

extension XCUIElement {
    /// Waits for the element's label to become `text`.
    @MainActor
    fileprivate func waitForLabel(equalTo text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    /// Waits for the element's label to change away from `text`.
    @MainActor
    fileprivate func waitForLabel(notEqualTo text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", text), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }
}
