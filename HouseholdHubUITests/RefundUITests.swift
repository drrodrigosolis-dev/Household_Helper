import XCTest

/// Sprint 20: Refund… on a purchase adds the money back as its own record; the purchase stays.
final class RefundUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPartialThenFullRefundKeepsThePurchase() {
        let app = launchApp()
        addViaQuickAdd(app, "120 shoes")
        openPurchase(app, containing: "shoes")

        refund(app, amount: "40", capture: "sprint20-refund-sheet-light")
        let summary = app.descendants(matching: .any)["editor.refundSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "The purchase should show what was refunded")
        XCTAssertTrue(waitForRow(app, identifier: "editor.refundSummary", toRead: "40.00"))
        captureScreen(app, named: "sprint20-purchase-partly-refunded-light")

        // The rest is pre-filled.
        app.buttons["editor.refund"].tap()
        let amount = app.textFields["refund.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Refund sheet did not open again")
        XCTAssertEqual(amount.value as? String, "80.00", "What is left should be pre-filled")
        tapSaveAndWaitForClose(app.buttons["refund.save"], closes: amount)
        let fully = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Fully refunded"))
            .firstMatch
        XCTAssertTrue(fully.waitForExistence(timeout: 10), "Nothing is left to refund")
        XCTAssertFalse(app.buttons["editor.refund"].exists, "Refund… goes away once all is back")
        captureScreen(app, named: "sprint20-purchase-fully-refunded-light")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let purchase = transactionRow(app, containing: "shoes")
        XCTAssertTrue(purchase.waitForExistence(timeout: 10), "The purchase stays in the list")
        let refunds = app.descendants(matching: .any).matching(identifier: "transaction.row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Refund"))
        XCTAssertEqual(refunds.count, 2, "Each refund is its own row")
        captureScreen(app, named: "sprint20-budget-list-light")
    }

    @MainActor
    func testRefundingAWishlistPurchaseAsksToKeepTheItem() {
        let app = launchApp(variant: .dark)
        addWishlistItem(app, name: "Desk lamp", estimate: "40")
        wishlistRow(app, containing: "Desk lamp").tap()
        app.buttons["wishlist.markPurchased"].tap()
        let confirm = app.buttons["wishlist.purchase.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Purchase sheet did not open")
        confirm.tap()
        XCTAssertTrue(waitForRow(app, identifier: "wishlist.status", toRead: "Purchased"))

        openPurchase(app, containing: "Desk lamp")
        app.buttons["editor.refund"].tap()
        let save = app.buttons["refund.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Refund sheet did not open")
        save.tap()
        // The alert's buttons: the purchase's editor behind it offers the same choice (review S5). By identifier and
        // first match: iOS 26 nests a button inside each alert button, both with the same identifier (L-018).
        let alert = app.alerts["Keep it on your wishlist?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "A full refund of a wishlist purchase should ask")
        let keep = alert.buttons["refund.keep"].firstMatch
        XCTAssertTrue(keep.exists)
        XCTAssertTrue(alert.buttons["refund.remove"].firstMatch.exists)
        captureScreen(app, named: "sprint20-wishlist-keep-or-remove-dark")
        keep.tap()
        // The choice closes the refund sheet (run 36362839424: it stayed open and the item unresolved).
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 10), .completed, "Keeping should close the refund")

        app.tabBars.buttons["Wishlist"].tap()
        let row = wishlistRow(app, containing: "Desk lamp")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Kept items stay on the wishlist")
        row.tap()
        XCTAssertTrue(waitForRow(app, identifier: "wishlist.status", toRead: "Wanted"), "Back to Wanted")
        XCTAssertTrue(app.buttons["wishlist.markPurchased"].exists, "It can be bought again")
        captureScreen(app, named: "sprint20-wishlist-item-back-dark")
    }

    @MainActor
    func testRefundSheetAtTheLargestTextSize() {
        let app = launchApp(variant: .largeText)
        addViaQuickAdd(app, "25 umbrella")
        openPurchase(app, containing: "umbrella")
        let refund = app.buttons["editor.refund"]
        XCTAssertTrue(scrollUntilExists(app, refund), "Refund… missing from the purchase")
        refund.tap()
        XCTAssertTrue(app.textFields["refund.amount"].waitForExistence(timeout: 5), "Refund sheet did not open")
        captureScreen(app, named: "sprint20-refund-sheet-largeText")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["editor.refundSummary"].exists, "Cancel refunds nothing")
    }

    // MARK: Helpers

    @MainActor
    private func openPurchase(_ app: XCUIApplication, containing text: String) {
        app.tabBars.buttons["Budget"].tap()
        let row = transactionRow(app, containing: text)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "'\(text)' missing from Budget")
        row.tap()
        XCTAssertTrue(app.navigationBars["Transaction"].waitForExistence(timeout: 10), "Editor did not open")
    }

    @MainActor
    private func refund(_ app: XCUIApplication, amount: String, capture: String? = nil) {
        let open = app.buttons["editor.refund"]
        XCTAssertTrue(scrollUntilExists(app, open), "Refund… missing from the purchase")
        open.tap()
        let field = app.textFields["refund.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Refund sheet did not open")
        replaceText(in: field, with: amount)
        if let capture {
            captureScreen(app, named: capture)
        }
        tapSaveAndWaitForClose(app.buttons["refund.save"], closes: field)
    }
}
