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

    /// Spec §24.5: moving between columns never requires dragging. Uses the detail's Move to… menu; a long press on
    /// the card races the drag and the context menu, so it is not a dependable test path (run 36205561992).
    @MainActor
    func testMoveToIsAvailableWithoutDragging() {
        let app = launchApp()
        addTask(app, title: "Book dentist")
        taskCard(app, containing: "Book dentist").tap()
        let moveTo = app.buttons["task.moveTo"]
        XCTAssertTrue(moveTo.waitForExistence(timeout: 5), "A non-drag Move to… action")
        moveTo.tap()
        let target = app.buttons["In Progress"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Move to… should list the other columns")
        target.tap()
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
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("call plumber tomorrow")
        app.segmentedControls["quickadd.type"].buttons["Task"].tap()
        app.buttons["quickadd.save"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save")
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(taskCard(app, containing: "call plumber").waitForExistence(timeout: 10), "Task missing")
    }

    /// Spec §7.10, §8.5: a custom column can be added, renamed, and deleted after choosing where its tasks go.
    /// Each row's actions menu is labeled "Actions for <name>", which is how the rows are found.
    @MainActor
    func testColumnCanBeAddedRenamedAndDeleted() {
        let app = launchApp()
        let tasksTab = app.tabBars.buttons["Tasks"]
        XCTAssertTrue(tasksTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        tasksTab.tap()
        let columnsButton = app.buttons["tasks.columns"]
        XCTAssertTrue(columnsButton.waitForExistence(timeout: 10), "Tasks has no Columns button")
        columnsButton.tap()
        XCTAssertTrue(app.navigationBars["Columns"].waitForExistence(timeout: 5), "Columns sheet did not open")

        let newName = app.textFields["columns.newName"]
        XCTAssertTrue(scrollUntilExists(app, newName), "New column field missing")
        focusAndType(newName, "Errands")
        app.buttons["Add column"].tap()
        let errands = app.buttons["Actions for Errands"]
        XCTAssertTrue(errands.waitForExistence(timeout: 10), "New column not listed")

        errands.tap()
        let rename = app.buttons["Rename"].firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "Column menu should offer Rename")
        rename.tap()
        let alert = app.alerts["Rename column"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Rename alert did not appear")
        replaceText(in: alert.textFields.firstMatch, with: "Chores")
        alert.buttons["Save"].tap()
        let chores = app.buttons["Actions for Chores"]
        XCTAssertTrue(chores.waitForExistence(timeout: 10), "Renamed column not listed")
        XCTAssertTrue(errands.waitForNonExistence(timeout: 5), "The old name should be gone")

        chores.tap()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "A custom column's menu should offer Delete")
        delete.tap()
        let move = app.buttons["Move tasks to To Do and delete"]
        XCTAssertTrue(move.waitForExistence(timeout: 5), "Delete must ask where the column's tasks go")
        move.tap()
        XCTAssertTrue(chores.waitForNonExistence(timeout: 10), "Deleted column still listed")
        XCTAssertTrue(app.buttons["Actions for To Do"].exists, "The default columns stay")
    }
}

extension XCTestCase {
    /// Adds a task through the Tasks tab's editor and waits for its card.
    /// Sprint 9: a task can link a transaction from its editor, and the detail shows the link.
    @MainActor
    func testTaskLinksATransaction() {
        let app = launchApp()
        addViaQuickAdd(app, "12 parking")
        addTask(app, title: "Get receipt")
        taskCard(app, containing: "Get receipt").tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let picker = app.buttons["task.editor.transaction"]
        XCTAssertTrue(scrollUntilExists(app, picker), "Transaction picker missing from the task editor")
        picker.tap()
        let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "parking")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The recent transaction is not offered")
        option.tap()
        app.buttons["task.editor.save"].tap()
        let linked = waitForRow(app, identifier: "task.transaction", toRead: "parking")
        XCTAssertTrue(linked, "Detail does not show the link")
    }

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
