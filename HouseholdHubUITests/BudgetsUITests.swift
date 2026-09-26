import XCTest

/// Sprint 11: category budgets driven end to end and captured for the walk.
final class BudgetsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddABudgetSpendAgainstItAndSeeItOnTheDashboard() {
        let app = launchApp()
        addDiningBudget(app, limit: "300")
        XCTAssertTrue(budgetRow(app, containing: "300.00 left").waitForExistence(timeout: 10), "New budget missing")
        captureScreen(app, named: "sprint11-budgets-light")

        addViaQuickAdd(app, "45 lunch #dining")
        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(
            budgetRow(app, containing: "255.00 left").waitForExistence(timeout: 10),
            "Spending in the category should come off the budget")

        app.tabBars.buttons["Dashboard"].tap()
        let card = app.buttons.matching(identifier: "dashboard.budget").firstMatch
        XCTAssertTrue(scrollUntilExists(app, card), "The Dashboard should show the budget")
        captureScreen(app, named: "sprint11-dashboard-budgets-light")
        card.tap()
        XCTAssertTrue(
            transactionRow(app, containing: "lunch").waitForExistence(timeout: 10),
            "A budget row opens that category's transactions")
    }

    @MainActor
    func testBudgetScreensInDarkAndLargestText() {
        for variant in [WalkVariant.dark, .largeText] {
            let app = launchApp(variant: variant)
            addDiningBudget(app, limit: "300", capture: "sprint11-budget-editor-\(variant.rawValue)")
            XCTAssertTrue(budgetRow(app, containing: "Dining").waitForExistence(timeout: 10))
            captureScreen(app, named: "sprint11-budgets-\(variant.rawValue)")
            app.terminate()
        }
    }

    // MARK: Helpers

    @MainActor
    private func addDiningBudget(_ app: XCUIApplication, limit: String, capture: String? = nil) {
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
        XCTAssertTrue(app.switches["budgetEditor.rollsOver"].exists, "Rollover switch missing")
        if let capture {
            captureScreen(app, named: capture)
        }
        app.buttons["budgetEditor.save"].tap()
    }

    @MainActor
    private func budgetRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "budget.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
