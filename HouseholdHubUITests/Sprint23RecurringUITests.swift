import XCTest

/// Sprint 23: recurring suggestions (F2) and budget alerts (F7). Quick Add can date a transaction at most six days
/// back and no launch fixture seeds history, so a real weekly or monthly pattern can't be built here: detection and
/// the suggestion rows are covered by `RecurringDetectorTests` and `RecurringSuggestionsModelTests`. This checks
/// what the UI can reach: same-day purchases are not a pattern, and the Budget alerts switch starts on.
final class Sprint23RecurringUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSameDayPurchasesAreNotSuggested() {
        let app = launchApp()
        for _ in 0..<3 {
            addViaQuickAdd(app, "17.99 Streaming Co")
        }
        app.tabBars.buttons["Budget"].tap()
        app.buttons["Recurring"].tap()
        XCTAssertTrue(app.buttons["recurring.addEmpty"].waitForExistence(timeout: 10), "Recurring should be empty")
        let suggestion = app.descendants(matching: .any)["recurring.suggestion"]
        XCTAssertFalse(suggestion.exists, "Three purchases on one day are not a recurring pattern")
        captureScreen(app, named: "sprint23-recurring-no-suggestions-light")
    }

    @MainActor
    func testBudgetAlertsSwitchStartsOn() {
        let app = launchApp()
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 30), "Tab bar never appeared")
        more.tap()
        app.buttons["Settings"].tap()
        let toggle = app.switches["settings.budgetAlerts"]
        XCTAssertTrue(scrollUntilExists(app, toggle), "Budget alerts missing from Settings › Reminders")
        XCTAssertEqual(toggle.value as? String, "1", "Budget alerts should start on")
        captureScreen(app, named: "sprint23-settings-budget-alerts-light")
    }
}
