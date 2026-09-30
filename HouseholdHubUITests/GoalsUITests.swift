import XCTest

/// Sprint 12: savings goals driven end to end and captured for the walk.
final class GoalsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddAGoalAndSeeItOnTheDashboard() {
        let app = launchApp()
        addGoal(app, name: "Trip", target: "500")
        XCTAssertTrue(goalRow(app, containing: "Trip").waitForExistence(timeout: 10), "New goal missing")
        captureScreen(app, named: "sprint12-goals-light")

        app.tabBars.buttons["Dashboard"].tap()
        let card = app.buttons.matching(identifier: "dashboard.goal").firstMatch
        XCTAssertTrue(scrollUntilExists(app, card), "The Dashboard should show the goal")
        captureScreen(app, named: "sprint12-dashboard-goals-light")
        card.tap()
        XCTAssertTrue(
            goalRow(app, containing: "Trip").waitForExistence(timeout: 10), "The goals card opens Wishlist › Goals")
    }

    @MainActor
    func testGoalScreensInDarkAndLargestText() {
        for variant in [WalkVariant.dark, .largeText] {
            let app = launchApp(variant: variant)
            addGoal(app, name: "Trip", target: "500", capture: "sprint12-goal-editor-\(variant.rawValue)")
            XCTAssertTrue(goalRow(app, containing: "Trip").waitForExistence(timeout: 10))
            captureScreen(app, named: "sprint12-goals-\(variant.rawValue)")
            app.terminate()
        }
    }

    // MARK: Helpers

    @MainActor
    private func addGoal(_ app: XCUIApplication, name: String, target: String, capture: String? = nil) {
        let wishlistTab = app.tabBars.buttons["Wishlist"]
        XCTAssertTrue(wishlistTab.waitForExistence(timeout: 30), "Tab bar never appeared")
        wishlistTab.tap()
        app.buttons["Goals"].tap()
        let add = app.buttons["goals.addEmpty"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Empty goals should offer Add goal")
        add.tap()
        let nameField = app.textFields["goalEditor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Goal editor did not open")
        nameField.tap()
        nameField.typeText(name)
        let targetField = app.textFields["goalEditor.target"]
        XCTAssertTrue(targetField.waitForExistence(timeout: 5))
        targetField.tap()
        targetField.typeText(target)
        XCTAssertTrue(app.switches["goalEditor.hasDate"].exists, "Target date switch missing")
        if let capture {
            captureScreen(app, named: capture)
        }
        app.buttons["goalEditor.save"].tap()
    }

    @MainActor
    private func goalRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "goal.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
