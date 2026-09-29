import XCTest

final class DashboardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDashboardReflectsNewExpenseAndDeepLinksIntoBudget() {
        let app = launchApp()
        addViaQuickAdd(app, "47.50 coffee")
        app.tabBars.buttons["Dashboard"].tap()
        let amount = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "47.50")).firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Current balance did not update after Quick Add")

        app.buttons["dashboard.pending"].tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5), "Pending card should open Budget")
    }

    /// L-034 walk: "I had to pay 80 dentist" left the merchant as "dentis". The merchant follows the whole line.
    @MainActor
    func testATypePhraseLineKeepsTheWholeMerchant() {
        let app = launchApp()
        let field = openQuickAdd(app)
        typeIntoQuickAdd(field, "I had to pay 80 dentist")
        let merchant = app.textFields["quickadd.notes"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 10), "The merchant field should show")
        let whole = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'dentist'"), object: merchant)
        XCTAssertEqual(
            XCTWaiter().wait(for: [whole], timeout: 5), .completed,
            "The merchant reads '\(merchant.value ?? "nil")', not 'dentist'")
    }

    @MainActor
    func testProjectedCardOpensRecurring() {
        let app = launchApp()
        let projected = app.buttons["dashboard.projected"]
        XCTAssertTrue(projected.waitForExistence(timeout: 10))
        projected.tap()
        XCTAssertTrue(app.buttons["recurring.addEmpty"].waitForExistence(timeout: 5))
    }

    /// v1 audit: Quick Add opens from the Current balance card, and a task in Recent activity opens the Tasks tab.
    @MainActor
    func testBalanceCardOpensQuickAddAndActivityRowsOpenTheirTab() {
        let app = launchApp()
        let add = app.buttons["dashboard.quickAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 30), "Current balance card has no Quick Add button")
        add.tap()
        let field = app.textFields["quickadd.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Quick Add sheet did not open from the card")
        typeIntoQuickAdd(field, "fix the shelf")
        app.segmentedControls["quickadd.type"].buttons["Task"].tap()
        tapQuickAddSave(app)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save the task")

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fix the shelf"))
            .firstMatch
        XCTAssertTrue(scrollUntilExists(app, row), "The new task is missing from Recent activity")
        row.tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5), "A task row should open Tasks")
    }
}
