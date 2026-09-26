import XCTest

/// Sprint 10: accounts and transfers, driven end to end and captured for the walk (light; dark and largest text
/// for the new screens).
final class AccountsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddAnAccountTransferToItAndSeeBothOnTheDashboard() {
        let app = launchApp()
        openAccounts(app)
        XCTAssertTrue(accountRow(app, containing: "Main account").waitForExistence(timeout: 10), "Main account missing")
        addAccount(app, name: "Savings", kind: "Savings", balance: "500")
        XCTAssertTrue(accountRow(app, containing: "Savings").waitForExistence(timeout: 10), "New account missing")
        captureScreen(app, named: "sprint10-accounts-light")

        app.tabBars.buttons["Budget"].tap()
        let newTransfer = app.buttons["budget.newTransfer"]
        XCTAssertTrue(newTransfer.waitForExistence(timeout: 10), "Two accounts should offer New transfer")
        newTransfer.tap()
        choose(app, picker: "transfer.to", option: "Savings")
        let amount = app.textFields["transfer.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("100")
        captureScreen(app, named: "sprint10-transfer-editor-light")
        app.buttons["transfer.save"].tap()
        XCTAssertTrue(
            transactionRow(app, containing: "Transfer to Savings").waitForExistence(timeout: 10),
            "The transfer should be listed")
        captureScreen(app, named: "sprint10-budget-transfer-light")

        app.tabBars.buttons["Dashboard"].tap()
        let rows = app.buttons.matching(identifier: "dashboard.account")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Dashboard should list the accounts")
        XCTAssertEqual(rows.count, 2)
        let savings = rows.matching(NSPredicate(format: "label CONTAINS %@", "600.00")).firstMatch
        XCTAssertTrue(savings.exists, "Savings holds its 500 plus the 100 transferred")
        captureScreen(app, named: "sprint10-dashboard-accounts-light")

        savings.tap()
        XCTAssertTrue(
            transactionRow(app, containing: "Transfer to Savings").waitForExistence(timeout: 10),
            "An account row opens Budget filtered to that account")
    }

    @MainActor
    func testAccountScreensInDarkAndLargestText() {
        for variant in [WalkVariant.dark, .largeText] {
            let app = launchApp(variant: variant)
            openAccounts(app)
            XCTAssertTrue(accountRow(app, containing: "Main account").waitForExistence(timeout: 10))
            captureScreen(app, named: "sprint10-accounts-\(variant.rawValue)")
            app.buttons["accounts.add"].tap()
            XCTAssertTrue(app.textFields["accountEditor.name"].waitForExistence(timeout: 5))
            captureScreen(app, named: "sprint10-account-editor-\(variant.rawValue)")
            app.terminate()
        }
    }

    // MARK: Helpers

    @MainActor
    private func openAccounts(_ app: XCUIApplication) {
        openSettings(app)
        let accounts = app.buttons["settings.accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 10), "Settings has no Accounts row")
        accounts.tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5), "Accounts did not open")
    }

    @MainActor
    private func addAccount(_ app: XCUIApplication, name: String, kind: String, balance: String) {
        app.buttons["accounts.add"].tap()
        let field = app.textFields["accountEditor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Account editor did not open")
        focusAndType(field, name)
        choose(app, picker: "accountEditor.kind", option: kind)
        let amount = app.textFields["accountEditor.balance"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replaceText(in: amount, with: balance)
        app.buttons["accountEditor.save"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 10), "Editor did not close on save")
    }

    /// Opens a menu-style picker by its identifier and picks an option by its visible title.
    @MainActor
    private func choose(_ app: XCUIApplication, picker identifier: String, option: String) {
        let picker = app.buttons[identifier]
        XCTAssertTrue(scrollUntilExists(app, picker), "Picker \(identifier) missing")
        picker.tap()
        let choice = app.buttons[option].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "Picker \(identifier) does not offer \(option)")
        choice.tap()
    }

    @MainActor
    private func accountRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "account.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
