import XCTest

final class WishlistUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMarkPurchasedRecordsOneLinkedExpense() {
        let app = launchApp()
        addWishlistItem(app, name: "Desk lamp", estimate: "40")
        let row = wishlistRow(app, containing: "Desk lamp")
        XCTAssertTrue(row.label.contains("40.00"), "Card should show the estimate: '\(row.label)'")
        row.tap()
        app.buttons["wishlist.markPurchased"].tap()
        let price = app.textFields["wishlist.purchase.price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5), "Purchase sheet did not open")
        XCTAssertEqual(price.value as? String, "40.00", "Price paid should start from the estimate")
        price.tap()
        price.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "37.99")
        app.buttons["wishlist.purchase.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Purchased"].waitForExistence(timeout: 10), "Item should read as purchased")

        app.tabBars.buttons["Budget"].tap()
        let expense = transactionRow(app, containing: "Desk lamp")
        XCTAssertTrue(expense.waitForExistence(timeout: 10), "Purchase missing from Budget")
        XCTAssertTrue(expense.label.contains("37.99"), "Expense should use the price paid: '\(expense.label)'")
        XCTAssertTrue(expense.label.contains("-"), "Purchase should read as an expense: '\(expense.label)'")
    }

    @MainActor
    func testDeletingAPurchasedItemOffersArchiveAndKeepsTheExpense() {
        let app = launchApp()
        addWishlistItem(app, name: "Rug", estimate: "120")
        wishlistRow(app, containing: "Rug").tap()
        app.buttons["wishlist.markPurchased"].tap()
        XCTAssertTrue(app.buttons["wishlist.purchase.confirm"].waitForExistence(timeout: 5))
        app.buttons["wishlist.purchase.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Purchased"].waitForExistence(timeout: 10))
        app.buttons["wishlist.delete"].tap()
        XCTAssertTrue(app.buttons["Archive item"].waitForExistence(timeout: 5), "Spec §8.2: offer archiving")
        app.buttons["Delete item"].tap()

        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(transactionRow(app, containing: "120.00").waitForExistence(timeout: 10), "Expense must stay")
    }

    @MainActor
    func testQuickAddWishlistSegmentCreatesAnItem() {
        let app = launchApp()
        app.buttons["quickadd.button"].tap()
        let field = app.textFields["quickadd.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("250 new bike")
        app.segmentedControls["quickadd.type"].buttons["Wishlist"].tap()
        app.buttons["quickadd.save"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save")

        app.tabBars.buttons["Wishlist"].tap()
        let row = wishlistRow(app, containing: "new bike")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Wishlist item missing")
        XCTAssertTrue(row.label.contains("250.00"), "Estimate should come from the text: '\(row.label)'")
        app.tabBars.buttons["Budget"].tap()
        XCTAssertFalse(transactionRow(app, containing: "new bike").waitForExistence(timeout: 2), "No expense yet")
    }
}

extension XCTestCase {
    /// Adds an item through the Wishlist tab's editor and waits for its row.
    @MainActor
    func addWishlistItem(_ app: XCUIApplication, name: String, estimate: String, capture: String? = nil) {
        app.tabBars.buttons["Wishlist"].tap()
        app.buttons["wishlist.add"].tap()
        let nameField = app.textFields["wishlist.editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Wishlist editor did not open")
        nameField.tap()
        nameField.typeText(name)
        if !estimate.isEmpty {
            let estimateField = app.textFields["wishlist.editor.estimate"]
            estimateField.tap()
            estimateField.typeText(estimate)
        }
        if let capture {
            captureScreen(app, named: capture)
        }
        app.buttons["wishlist.editor.save"].tap()
        XCTAssertTrue(wishlistRow(app, containing: name).waitForExistence(timeout: 10), "'\(name)' not listed")
    }

    @MainActor
    func wishlistRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "wishlist.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
