import XCTest

final class TasksUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddedTaskLandsInFirstColumnAndCompletesIntoDone() {
        let app = launchApp()
        addTask(app, title: "Fix dripping tap")
        taskCard(app, containing: "Fix dripping tap").tap()
        XCTAssertTrue(waitForRow(app, identifier: "task.column", toRead: "To Do"), "New tasks start in To Do")
        app.buttons["task.complete"].tap()
        XCTAssertTrue(waitForRow(app, identifier: "task.column", toRead: "Done"), "Completing moves it to Done")
    }

    @MainActor
    func testMoveToIsAvailableWithoutDragging() {
        let app = launchApp()
        addTask(app, title: "Book dentist")
        let card = taskCard(app, containing: "Book dentist")
        card.press(forDuration: 1.2)
        let moveTo = app.buttons["Move to…"]
        XCTAssertTrue(moveTo.waitForExistence(timeout: 5), "Spec §24.5: a non-drag Move to… action")
        moveTo.tap()
        app.buttons["In Progress"].firstMatch.tap()
        taskCard(app, containing: "Book dentist").tap()
        XCTAssertTrue(waitForRow(app, identifier: "task.column", toRead: "In Progress"))
    }

    @MainActor
    func testSubtasksCanBeAddedAndCheckedOff() {
        let app = launchApp()
        addTask(app, title: "Paint hallway")
        taskCard(app, containing: "Paint hallway").tap()
        let field = app.textFields["task.newSubtask"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusAndType(field, "Buy paint")
        app.buttons["task.addSubtask"].tap()
        let subtask = app.buttons.matching(identifier: "task.subtask").firstMatch
        XCTAssertTrue(subtask.waitForExistence(timeout: 5), "Subtask not added")
        subtask.tap()
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Done"), object: subtask)
        XCTAssertEqual(XCTWaiter().wait(for: [checked], timeout: 5), .completed, "Subtask did not check off")
    }

    @MainActor
    func testQuickAddTaskSegmentCreatesATask() {
        let app = launchApp()
        app.buttons["quickadd.button"].tap()
        let field = app.textFields["quickadd.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("call plumber tomorrow")
        app.segmentedControls["quickadd.type"].buttons["Task"].tap()
        app.buttons["quickadd.save"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save")
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(taskCard(app, containing: "call plumber").waitForExistence(timeout: 10), "Task missing")
    }
}

extension XCTestCase {
    /// Adds a task through the Tasks tab's editor and waits for its card.
    @MainActor
    func addTask(_ app: XCUIApplication, title: String, capture: String? = nil) {
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["tasks.add"].tap()
        let field = app.textFields["task.editor.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Task editor did not open")
        focusAndType(field, title)
        if let capture {
            captureScreen(app, named: capture)
        }
        app.buttons["task.editor.save"].tap()
        XCTAssertTrue(taskCard(app, containing: title).waitForExistence(timeout: 10), "'\(title)' not on the board")
    }

    @MainActor
    func taskCard(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "task.card")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
