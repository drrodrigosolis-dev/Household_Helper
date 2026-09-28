import XCTest

/// Sprint 24 (item 4): contextual tips appear where the plan says they should. Launched with `-uiTesting
/// -uiTestingTips`, which resets TipKit's datastore and forces every tip to show regardless of its own rule, so a
/// tip whose rule normally waits for a second visit (Bulk select, Budget history) is visible on the first one here.
final class Sprint24TipsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTipsAppearWhereExpectedLight() {
        assertTips(variant: .light)
    }

    @MainActor
    func testTipsAppearWhereExpectedDark() {
        assertTips(variant: .dark)
    }

    @MainActor
    private func assertTips(variant: WalkVariant) {
        let suffix = variant == .dark ? "dark" : "light"
        let app = launchApp(variant: variant, tips: true)

        // 1. Bulk select, on Budget's "Select" toolbar button.
        let budgetTab = app.tabBars.buttons["Budget"]
        XCTAssertTrue(budgetTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        budgetTab.tap()
        let bulkSelectTitle = app.staticTexts["Change several at once"]
        XCTAssertTrue(bulkSelectTitle.waitForExistence(timeout: 10), "Bulk select tip did not appear over Select")
        captureScreen(app, named: "sprint24-tip-bulkSelect-\(suffix)")

        // 2. Split…, on the transaction editor's Split… button.
        addViaQuickAdd(app, "100 hardware")
        let row = transactionRow(app, containing: "hardware")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "'hardware' missing from Budget")
        row.tap()
        XCTAssertTrue(app.navigationBars["Transaction"].waitForExistence(timeout: 10), "Editor did not open")
        let split = app.buttons["editor.split"]
        XCTAssertTrue(scrollUntilExists(app, split), "Split… missing from the editor")
        let splitTipTitle = app.staticTexts["Split one payment"]
        XCTAssertTrue(splitTipTitle.waitForExistence(timeout: 10), "Split tip did not appear over Split…")
        captureScreen(app, named: "sprint24-tip-split-\(suffix)")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 3. Budget history, on the Budgets month arrows.
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Transaction"])
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "Editor should close")
        app.buttons["Budgets"].tap()
        // With no budget the screen is its empty state, which has no month arrows (CI run 36465178943).
        addDiningBudget(app, limit: "200")
        let monthArrows = app.buttons["budgets.nextMonth"]
        XCTAssertTrue(monthArrows.waitForExistence(timeout: 10), "Budgets month arrows missing")
        let budgetHistoryTitle = app.staticTexts["Look back"]
        XCTAssertTrue(budgetHistoryTitle.waitForExistence(timeout: 10), "Budget history tip did not appear")
        captureScreen(app, named: "sprint24-tip-budgetHistory-\(suffix)")
    }

    /// From an empty Budgets screen: a Dining budget, saved.
    @MainActor
    private func addDiningBudget(_ app: XCUIApplication, limit: String) {
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
}
