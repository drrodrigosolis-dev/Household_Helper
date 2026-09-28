import XCTest

/// Sprint 26: a task can have a time on its due day, shown on the card and in the detail, and Settings › Reminders
/// has a "Reminder default time". Notifications can't be asserted here; `TaskDueTimeTests` covers when they fire.
final class TaskTimeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testATaskWithADateAndTimeShowsTheTime() {
        // Every locale's short time has a colon ("6:30 PM", "18:30"); the date, priority and title here have none.
        let showsATime = NSPredicate(format: "label CONTAINS %@", ":")
        let app = launchApp()
        let tasksTab = app.tabBars.buttons["Tasks"]
        XCTAssertTrue(tasksTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        tasksTab.tap()
        app.buttons["tasks.add"].tap()
        let field = app.textFields["task.editor.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Task editor did not open")
        focusAndType(field, "Call the vet")
        XCTAssertFalse(app.switches["task.editor.hasDueTime"].exists, "No time without a due date")
        let dueSwitch = app.switches["task.editor.hasDueDate"]
        XCTAssertTrue(dueSwitch.waitForExistence(timeout: 5))
        dueSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let timeSwitch = app.switches["task.editor.hasDueTime"]
        XCTAssertTrue(scrollUntilExists(app, timeSwitch), "Due time appears once there is a due date")
        XCTAssertEqual(timeSwitch.value as? String, "0", "A new task has no time")
        timeSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let picker = app.descendants(matching: .any).matching(identifier: "task.editor.dueTime").firstMatch
        XCTAssertTrue(scrollUntilExists(app, picker), "The time picker appears once the time is on")
        captureScreen(app, named: "sprint26-task-editor-time-light")
        app.buttons["task.editor.save"].tap()

        let card = app.descendants(matching: .any).matching(identifier: "task.card")
            .matching(NSPredicate(format: "label CONTAINS %@", "Call the vet")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The task is not on the board")
        let timed = XCTNSPredicateExpectation(predicate: showsATime, object: card)
        XCTAssertEqual(XCTWaiter().wait(for: [timed], timeout: 5), .completed, "The card should show the time")
        captureScreen(app, named: "sprint26-board-time-light")
        card.tap()
        let due = app.descendants(matching: .any)["task.due"]
        XCTAssertTrue(due.waitForExistence(timeout: 5), "The detail should show the due date")
        let detailTimed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", ":", ":"), object: due)
        XCTAssertEqual(XCTWaiter().wait(for: [detailTimed], timeout: 5), .completed, "The detail should show the time")

        // Turning the time off leaves the date only.
        app.buttons["Edit"].tap()
        let offSwitch = app.switches["task.editor.hasDueTime"]
        XCTAssertTrue(scrollUntilExists(app, offSwitch))
        XCTAssertEqual(offSwitch.value as? String, "1", "The editor shows the saved time")
        offSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.buttons["task.editor.save"].tap()
        let untimed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (label CONTAINS %@) AND NOT (value CONTAINS %@)", ":", ":"),
            object: due)
        XCTAssertEqual(XCTWaiter().wait(for: [untimed], timeout: 10), .completed, "The time should be gone")
    }

    @MainActor
    func testTheReminderDefaultTimeCanBeChanged() {
        let app = launchApp()
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 30), "Tab bar never appeared")
        more.tap()
        app.buttons["Settings"].tap()
        let note = app.staticTexts["settings.reminderDefaultTimeNote"]
        XCTAssertTrue(scrollUntilExists(app, note), "The Reminders footer should name the default time")
        let before = note.label
        let picker = app.descendants(matching: .any).matching(identifier: "settings.reminderDefaultTime").firstMatch
        XCTAssertTrue(scrollUntilExists(app, picker), "Reminder default time missing from Settings › Reminders")
        captureScreen(app, named: "sprint26-settings-default-time-light")

        // The compact picker opens its wheels; one swipe on the hour wheel picks another hour.
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let hour = app.pickerWheels.firstMatch
        XCTAssertTrue(hour.waitForExistence(timeout: 5), "The time picker did not open")
        hour.swipeUp()
        // Closes the wheels with a tap away from them (the navigation title).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: note)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed, "The default time did not change")
        captureScreen(app, named: "sprint26-settings-default-time-changed-light")
    }
}
