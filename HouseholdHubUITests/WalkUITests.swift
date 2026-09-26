import XCTest

/// Screenshot walk of every primary screen in each presentation variant. Reviewed by eye before an item is ☑ walked.
final class WalkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkLight() {
        walkPrimaryScreens(.light)
    }

    @MainActor
    func testWalkDark() {
        walkPrimaryScreens(.dark)
    }

    @MainActor
    func testWalkLargeText() {
        walkPrimaryScreens(.largeText)
    }

    @MainActor
    private func walkPrimaryScreens(_ variant: WalkVariant) {
        let app = launchApp(variant: variant)
        addViaQuickAdd(app, "47.50 coffee")
        addViaQuickAdd(app, "+ 1200 paycheck")
        let field = openQuickAdd(app)
        field.tap()
        field.typeText("32.10 groceries yesterday")
        captureScreen(app, named: "\(variant.rawValue)-QuickAdd")
        app.buttons["Cancel"].tap()
        for tab in ["Dashboard", "Budget", "Wishlist", "Tasks", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Tab button '\(tab)' missing")
            button.tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 5))
            captureScreen(app, named: "\(variant.rawValue)-\(tab)")
        }
        walkSecondaryScreens(app, variant)
        walkWishlist(app, variant)
        walkTasks(app, variant)
        walkAnalytics(app, variant)
    }

    /// Analytics with the walk's transactions and purchase: summary and category chart, then the trend and merchants.
    @MainActor
    private func walkAnalytics(_ app: XCUIApplication, _ variant: WalkVariant) {
        openAnalytics(app)
        XCTAssertTrue(waitForRow(app, identifier: "analytics.net", toRead: "Net"), "Analytics report didn't load")
        let category = app.buttons.matching(identifier: "analytics.category").firstMatch
        XCTAssertTrue(scrollUntilExists(app, category), "Spending by category missing")
        captureScreen(app, named: "\(variant.rawValue)-Analytics")
        app.swipeUp()
        app.swipeUp()
        captureScreen(app, named: "\(variant.rawValue)-Analytics-trend")
    }

    /// Task editor, board, detail with a subtask, column management, and Quick Add's Task segment.
    @MainActor
    private func walkTasks(_ app: XCUIApplication, _ variant: WalkVariant) {
        let prefix = variant.rawValue
        addTask(app, title: "Fix dripping tap", capture: "\(prefix)-TaskEditor")
        addTask(app, title: "Book dentist")
        captureScreen(app, named: "\(prefix)-Tasks-board")
        taskCard(app, containing: "Fix dripping tap").tap()
        let field = app.textFields["task.newSubtask"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        focusAndType(field, "Buy washer")
        app.buttons["task.addSubtask"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "task.subtask").firstMatch.waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-TaskDetail")
        app.navigationBars.buttons["Tasks"].tap()
        app.buttons["tasks.columns"].tap()
        XCTAssertTrue(app.navigationBars["Columns"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Columns")
        app.navigationBars["Columns"].buttons["Done"].tap()

        let quick = openQuickAdd(app)
        quick.tap()
        quick.typeText("call plumber tomorrow")
        app.segmentedControls["quickadd.type"].buttons["Task"].tap()
        captureScreen(app, named: "\(prefix)-QuickAdd-task")
        app.buttons["Cancel"].tap()
    }

    /// Wishlist editor, list, grid, detail, and the Mark Purchased sheet, plus Quick Add's Wishlist segment.
    @MainActor
    private func walkWishlist(_ app: XCUIApplication, _ variant: WalkVariant) {
        let prefix = variant.rawValue
        addWishlistItem(app, name: "Standing desk", estimate: "450", capture: "\(prefix)-WishlistEditor")
        addWishlistItem(app, name: "Espresso machine", estimate: "")
        captureScreen(app, named: "\(prefix)-Wishlist-list")
        app.buttons["wishlist.layout"].tap()
        captureScreen(app, named: "\(prefix)-Wishlist-grid")
        app.buttons["wishlist.layout"].tap()
        wishlistRow(app, containing: "Standing desk").tap()
        XCTAssertTrue(app.buttons["wishlist.markPurchased"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-WishlistDetail")
        app.buttons["wishlist.markPurchased"].tap()
        XCTAssertTrue(app.buttons["wishlist.purchase.confirm"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-WishlistPurchase")
        app.buttons["wishlist.purchase.confirm"].tap()
        let purchased = waitForRow(app, identifier: "wishlist.status", toRead: "Purchased")
        XCTAssertTrue(purchased, "Item should read as purchased")
        captureScreen(app, named: "\(prefix)-WishlistDetail-purchased")
        app.tabBars.buttons["Dashboard"].tap()
        captureScreen(app, named: "\(prefix)-Dashboard-activity")

        let field = openQuickAdd(app)
        field.tap()
        field.typeText("80 plant stand")
        app.segmentedControls["quickadd.type"].buttons["Wishlist"].tap()
        captureScreen(app, named: "\(prefix)-QuickAdd-wishlist")
        app.buttons["Cancel"].tap()
    }

    /// Recurring, Settings and Categories, including their editors.
    @MainActor
    private func walkSecondaryScreens(_ app: XCUIApplication, _ variant: WalkVariant) {
        let prefix = variant.rawValue
        app.tabBars.buttons["Budget"].tap()
        app.buttons["Recurring"].tap()
        XCTAssertTrue(app.buttons["recurring.addEmpty"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Recurring-empty")
        app.buttons["recurring.addEmpty"].tap()
        XCTAssertTrue(app.textFields["recurringEditor.name"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-RecurringEditor")
        app.buttons["Cancel"].tap()
        app.buttons["Transactions"].tap()

        app.tabBars.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Settings")
        app.buttons["settings.categories"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-Categories")
        app.buttons["categories.add"].tap()
        XCTAssertTrue(app.textFields["categoryEditor.name"].waitForExistence(timeout: 5))
        captureScreen(app, named: "\(prefix)-CategoryEditor")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["settings.data"].tap()
        XCTAssertTrue(app.navigationBars["Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["data.backup"].exists && app.buttons["data.restore"].exists)
        captureScreen(app, named: "\(prefix)-Data")
    }
}
