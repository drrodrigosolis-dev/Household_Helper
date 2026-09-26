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
        replaceText(in: price, with: "37.99")
        app.buttons["wishlist.purchase.confirm"].tap()
        let purchased = waitForRow(app, identifier: "wishlist.status", toRead: "Purchased")
        XCTAssertTrue(purchased, "Item should read as purchased")

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
        XCTAssertTrue(waitForRow(app, identifier: "wishlist.status", toRead: "Purchased"))
        app.buttons["wishlist.delete"].tap()
        XCTAssertTrue(app.buttons["Archive item"].waitForExistence(timeout: 5), "Spec §8.2: offer archiving")
        app.buttons["Delete item"].tap()

        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(transactionRow(app, containing: "120.00").waitForExistence(timeout: 10), "Expense must stay")
    }

    @MainActor
    func testQuickAddWishlistSegmentCreatesAnItem() {
        let app = launchApp()
        let field = openQuickAdd(app)
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

    /// Spec §24.2: the status chip filters the list (Active by default hides purchased items), and the layout
    /// toggle switches between list and grid without losing the cards.
    @MainActor
    func testStatusFilterChipsAndGridListToggle() {
        let app = launchApp()
        addWishlistItem(app, name: "Desk lamp", estimate: "40")
        addWishlistItem(app, name: "Rug", estimate: "120")
        let lamp = wishlistRow(app, containing: "Desk lamp")
        let rug = wishlistRow(app, containing: "Rug")
        lamp.tap()
        let markPurchased = app.buttons["wishlist.markPurchased"]
        XCTAssertTrue(markPurchased.waitForExistence(timeout: 5), "Item detail did not open")
        markPurchased.tap()
        let confirm = app.buttons["wishlist.purchase.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Purchase sheet did not open")
        confirm.tap()
        XCTAssertTrue(waitForRow(app, identifier: "wishlist.status", toRead: "Purchased"))
        app.navigationBars.buttons["Wishlist"].tap()

        let status = app.buttons["wishlist.statusFilter"]
        XCTAssertTrue(status.waitForExistence(timeout: 5), "Status filter chip missing")
        XCTAssertEqual(status.value as? String, "Active", "The list starts on Active items")
        XCTAssertTrue(rug.waitForExistence(timeout: 10), "A wanted item is active")
        XCTAssertTrue(lamp.waitForNonExistence(timeout: 10), "A purchased item is not active")

        chooseWishlistStatus(app, "Purchased")
        XCTAssertTrue(lamp.waitForExistence(timeout: 10), "Purchased filter should list the purchased item")
        XCTAssertTrue(rug.waitForNonExistence(timeout: 10), "Purchased filter should hide the wanted item")
        chooseWishlistStatus(app, "All")
        XCTAssertTrue(lamp.waitForExistence(timeout: 10) && rug.waitForExistence(timeout: 10), "All lists both")

        // The layout is remembered on the device (@AppStorage), so start from the list whatever an earlier run left.
        let layout = app.buttons["wishlist.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5), "Layout toggle missing")
        if layout.label == "Show as list" {
            layout.tap()
        }
        XCTAssertTrue(waitForLabel(layout, "Show as grid"), "List layout should offer the grid")
        layout.tap()
        XCTAssertTrue(waitForLabel(layout, "Show as list"), "Grid layout should offer the list")
        XCTAssertTrue(lamp.waitForExistence(timeout: 10) && rug.waitForExistence(timeout: 10), "Grid shows both")
        layout.tap()
        XCTAssertTrue(waitForLabel(layout, "Show as grid"), "Toggling again should return to the list")
        XCTAssertTrue(rug.waitForExistence(timeout: 10), "List shows the items again")
    }

    /// Links go both ways (spec §2.1): a task that links a wishlist item from its editor is listed on that item.
    @MainActor
    func testItemDetailListsTheTasksThatLinkIt() {
        let app = launchApp()
        addWishlistItem(app, name: "Desk lamp", estimate: "40")
        addTask(app, title: "Measure the desk")
        taskCard(app, containing: "Measure the desk").tap()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Task detail did not open")
        edit.tap()
        let picker = app.buttons["task.editor.wishlist"]
        XCTAssertTrue(scrollUntilExists(app, picker), "Wishlist item picker missing from the task editor")
        picker.tap()
        let option = app.buttons["Desk lamp"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "The open wishlist item is not offered")
        option.tap()
        app.buttons["task.editor.save"].tap()
        XCTAssertTrue(waitForRow(app, identifier: "task.column", toRead: "To Do"), "Editor did not return to detail")

        app.tabBars.buttons["Wishlist"].tap()
        let row = wishlistRow(app, containing: "Desk lamp")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let linked = app.descendants(matching: .any).matching(identifier: "wishlist.linkedTask").firstMatch
        XCTAssertTrue(scrollUntilExists(app, linked), "The item should list the task that links it")
        XCTAssertTrue(linked.label.contains("Measure the desk"), "Linked task row reads '\(linked.label)'")
    }

    @MainActor
    private func chooseWishlistStatus(_ app: XCUIApplication, _ title: String) {
        let chip = app.buttons["wishlist.statusFilter"]
        chip.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Status menu should offer '\(title)'")
        option.tap()
        let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [chosen], timeout: 5), .completed, "Chip should read '\(title)'")
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
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
        focusAndType(nameField, name)
        if !estimate.isEmpty {
            let estimateField = app.textFields["wishlist.editor.estimate"]
            focusAndType(estimateField, estimate)
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
