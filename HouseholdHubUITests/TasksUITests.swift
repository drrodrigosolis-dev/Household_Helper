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
        typeIntoQuickAdd(field, "call plumber tomorrow")
        app.segmentedControls["quickadd.type"].buttons["Task"].tap()
        tapQuickAddSave(app)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save")
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(taskCard(app, containing: "call plumber").waitForExistence(timeout: 10), "Task missing")
    }

    /// Sprint 18: each column is 2/3 of the screen at the left edge with the next one peeking in (owner decision),
    /// and a task dropped on the next column brings that column into focus at the left edge.
    @MainActor
    func testColumnsAreTwoThirdsWideAndADropFocusesTheNextColumn() {
        let app = launchApp()
        addTask(app, title: "Water plants")
        let window = app.windows.firstMatch.frame
        let toDo = columnHeader(app, "To Do")
        XCTAssertTrue(toDo.waitForExistence(timeout: 5), "No To Do column")
        // The header sits inside the column's 12 pt padding on each side.
        let share = (toDo.frame.width + 24) / window.width
        XCTAssertEqual(share, 2.0 / 3.0, accuracy: 0.04, "A column should be 2/3 of the screen wide")
        // The header sits 12 pt inside its column, which starts 16 pt from the edge.
        let leftEdge = window.minX + 28
        XCTAssertEqual(toDo.frame.minX, leftEdge, accuracy: 8, "The first column should start at the left edge")
        captureScreen(app, named: "sprint18-board-light")

        let card = taskCard(app, containing: "Water plants")
        let peek = app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: peek, withVelocity: .default, thenHoldForDuration: 0.2)
        let inProgress = columnHeader(app, "In Progress")
        // Frames are read on the main actor, so this polls instead of using a predicate expectation.
        let deadline = Date.now.addingTimeInterval(10)
        while abs(inProgress.frame.minX - leftEdge) >= 8, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(inProgress.frame.minX, leftEdge, accuracy: 8, "In Progress was not focused")
        XCTAssertEqual(card.frame.minX, leftEdge, accuracy: 8, "The card should be in the focused column")
        captureScreen(app, named: "sprint18-board-after-drop-light")
        card.tap()
        XCTAssertTrue(waitForRow(app, identifier: "task.column", toRead: "In Progress"), "The drop did not move it")
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

    /// Sprint 13: a weekly task, once completed, leaves a new open copy on the board with the repeat.
    @MainActor
    func testCompletingARepeatingTaskAddsTheNextOne() {
        let app = launchApp()
        app.tabBars.buttons["Tasks"].tap()
        app.buttons["tasks.add"].tap()
        let field = app.textFields["task.editor.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Task editor did not open")
        focusAndType(field, "Take out recycling")
        let dueSwitch = app.switches["task.editor.hasDueDate"]
        XCTAssertTrue(dueSwitch.waitForExistence(timeout: 5))
        dueSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let repeatPicker = app.buttons["task.editor.repeat"]
        XCTAssertTrue(repeatPicker.waitForExistence(timeout: 5), "Repeat appears once there is a due date")
        repeatPicker.tap()
        let weekly = app.buttons["Weekly"].firstMatch
        XCTAssertTrue(weekly.waitForExistence(timeout: 5), "Weekly should be offered")
        weekly.tap()
        captureScreen(app, named: "sprint13-task-editor-repeat-light")
        app.buttons["task.editor.save"].tap()

        let card = taskCard(app, containing: "Take out recycling")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        captureScreen(app, named: "sprint13-board-repeat-light")
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["task.repeats"].waitForExistence(timeout: 5), "Repeat not shown")
        app.buttons["task.complete"].tap()
        XCTAssertTrue(waitForRow(app, identifier: "task.column", toRead: "Done"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // The Done column may be off screen; the open copy is in the first column.
        let open = app.descendants(matching: .any).matching(identifier: "task.card")
            .matching(
                NSPredicate(
                    format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "Take out recycling", "Completed")
            ).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "The next, open task should be on the board")
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

    /// A column's header reads "<name>, <n> tasks".
    @MainActor
    func columnHeader(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "\(name),", "tasks")).firstMatch
    }

    @MainActor
    func taskCard(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "task.card")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
