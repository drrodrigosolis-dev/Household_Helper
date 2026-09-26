import XCTest

/// The widget itself can't be driven from XCUITest; these cover what it relies on in the app (spec §24.4).
final class WidgetUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The widget's Quick Add link opens the Quick Add sheet over the current tab.
    @MainActor
    func testQuickAddLinkOpensQuickAdd() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["quickadd.button"].waitForExistence(timeout: 30), "App never finished launching")
        let url = try XCTUnwrap(URL(string: "householdhub://quickadd"))
        app.open(url)
        XCTAssertTrue(app.textFields["quickadd.text"].waitForExistence(timeout: 10), "Link did not open Quick Add")
    }

    /// Settings offers the switch that hides amounts in the widget, on by default.
    @MainActor
    func testWidgetAmountsSwitchIsInSettings() {
        let app = launchApp()
        app.tabBars.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let toggle = app.switches["settings.widgetShowsBalance"]
        XCTAssertTrue(scrollUntilExists(app, toggle), "Widget switch missing from Settings")
        XCTAssertEqual(toggle.value as? String, "1", "Widget amounts should be shown by default")
    }
}
