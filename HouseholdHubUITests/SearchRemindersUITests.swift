import XCTest

/// Sprint 14: search narrows a tab's list; the reminder switches are in Settings and start off.
final class SearchRemindersUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTaskSearchNarrowsTheBoard() {
        let app = launchApp()
        let tasksTab = app.tabBars.buttons["Tasks"]
        XCTAssertTrue(tasksTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        tasksTab.tap()
        for title in ["Call plumber", "Renew passport"] {
            app.buttons["tasks.add"].tap()
            let field = app.textFields["task.editor.title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5), "Task editor did not open")
            focusAndType(field, title)
            app.buttons["task.editor.save"].tap()
            XCTAssertTrue(card(app, title).waitForExistence(timeout: 10), "'\(title)' not on the board")
        }
        let search = searchField(app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Tasks should offer search")
        search.tap()
        search.typeText("pássport")
        XCTAssertTrue(card(app, "Renew passport").waitForExistence(timeout: 5), "Accents are ignored")
        let hidden = NSPredicate(format: "exists == false")
        let gone = XCTNSPredicateExpectation(predicate: hidden, object: card(app, "Call plumber"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Non-matching tasks are hidden")
        captureScreen(app, named: "sprint14-task-search-light")
    }

    @MainActor
    func testReminderSwitchesStartOff() {
        let app = launchApp()
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 30), "Tab bar never appeared")
        more.tap()
        app.buttons["Settings"].tap()
        for identifier in ["settings.remindTasks", "settings.remindBills"] {
            let toggle = app.switches[identifier]
            XCTAssertTrue(scrollUntilExists(app, toggle), "\(identifier) missing from Settings")
            XCTAssertEqual(toggle.value as? String, "0", "\(identifier) should start off")
        }
        captureScreen(app, named: "sprint14-settings-reminders-light")
    }

    // MARK: Helpers

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

    @MainActor
    private func card(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "task.card")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
