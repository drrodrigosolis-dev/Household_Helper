import XCTest

final class SettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Spec §24.2 Backup and export: CSV export is offered, disabled while there is nothing to export and enabled
    /// once a transaction exists. The system file exporter it opens is not driven (an out-of-app sheet).
    /// Sprint 15: CSV import is offered in Data and enabled even with no data (the file picker is not driven).
    @MainActor
    func testCSVImportIsOffered() {
        let app = launchApp()
        openSettings(app)
        app.buttons["settings.data"].tap()
        XCTAssertTrue(app.navigationBars["Data"].waitForExistence(timeout: 5), "Data did not open")
        let importButton = app.buttons["data.importCSV"]
        XCTAssertTrue(scrollUntilExists(app, importButton), "CSV import button missing")
        XCTAssertTrue(importButton.isEnabled)
        captureScreen(app, named: "sprint15-data-import-light")
    }

    @MainActor
    func testCSVExportIsEnabledOnceThereIsATransaction() {
        let app = launchApp()
        openSettings(app)
        app.buttons["settings.data"].tap()
        XCTAssertTrue(app.navigationBars["Data"].waitForExistence(timeout: 5), "Backup and export did not open")
        let csv = app.buttons["data.csv"]
        XCTAssertTrue(csv.waitForExistence(timeout: 5), "CSV export button missing")
        XCTAssertFalse(csv.isEnabled, "With no transactions there is nothing to export")

        // Back to the More root, which has the Quick Add button, record one expense, and come back.
        app.navigationBars.buttons["Settings"].tap()
        app.navigationBars.buttons["More"].tap()
        addViaQuickAdd(app, "12 coffee")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["settings.data"].tap()
        XCTAssertTrue(csv.waitForExistence(timeout: 5), "CSV export button missing")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: csv)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed, "CSV export should be enabled")
        XCTAssertTrue(csv.isHittable, "CSV export should be tappable")
    }

    /// Spec §12: UI tests run without the on-device model (`AppInfo.onDeviceModelAvailable` is false under
    /// -uiTesting), so every switch reads off and is disabled, and the footer says why.
    @MainActor
    func testIntelligenceSwitchesAreOffAndDisabledWithoutTheModel() {
        let app = launchApp()
        openSettings(app)
        app.buttons["settings.intelligence"].tap()
        XCTAssertTrue(app.navigationBars["Intelligence"].waitForExistence(timeout: 5), "Intelligence did not open")
        for title in ["Quick Add understanding", "Category suggestions", "Analytics summaries"] {
            let toggle = app.switches[title].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Switch '\(title)' missing")
            XCTAssertFalse(toggle.isEnabled, "'\(title)' can't be turned on without the model")
            XCTAssertEqual(toggle.value as? String, "0", "'\(title)' should read off without the model")
        }
        let footer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Quick Add and categories work without it")
        ).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "The footer should explain the model is unavailable")
    }

    /// Spec §24.2 Appearance: the theme picker stores the choice and reads it back.
    @MainActor
    func testThemeCanBeSetToDarkAndBackToSystem() {
        let app = launchApp()
        openSettings(app)
        let theme = app.buttons["settings.theme"]
        XCTAssertTrue(scrollUntilExists(app, theme), "Theme picker missing")
        if !theme.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(waitForRow(app, identifier: "settings.theme", toRead: "System"), "Theme starts on System")
        chooseTheme(app, "Dark")
        chooseTheme(app, "System")
    }

    /// Spec §6.3, §9.1: with nothing recorded the currency can still change, and a new starting balance is saved
    /// only after confirming, then shown in Settings.
    @MainActor
    func testHouseholdStartingBalanceChangeIsConfirmedAndShown() {
        let app = launchApp()
        openSettings(app)
        let household = app.buttons["settings.household"]
        XCTAssertTrue(scrollUntilExists(app, household), "Edit Household missing from Settings")
        household.tap()
        XCTAssertTrue(app.navigationBars["Household"].waitForExistence(timeout: 5), "Household editor did not open")
        let currency = app.descendants(matching: .any)["household.currency"]
        XCTAssertTrue(currency.waitForExistence(timeout: 10), "Nothing is recorded, so the currency picker is shown")

        let balance = app.textFields["household.balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "Starting balance field missing")
        replaceText(in: balance, with: "250")
        app.buttons["household.save"].tap()
        let confirm = app.buttons["Change Starting Balance"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "A new baseline must be confirmed first")
        confirm.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Editor did not close on save")
        let shown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "250.00"))
            .firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 10), "Settings should show the new starting balance")
    }

    @MainActor
    private func chooseTheme(_ app: XCUIApplication, _ title: String) {
        app.buttons["settings.theme"].tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Theme menu should offer '\(title)'")
        option.tap()
        let chosen = waitForRow(app, identifier: "settings.theme", toRead: title)
        XCTAssertTrue(chosen, "Theme picker should read '\(title)'")
    }
}

extension XCTestCase {
    /// Opens More › Settings. Waits for the tab bar first: a cold simulator launch can take 20 s or more.
    @MainActor
    func openSettings(_ app: XCUIApplication) {
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 30), "Tab bar never appeared")
        more.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "More has no Settings row")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open")
    }
}
