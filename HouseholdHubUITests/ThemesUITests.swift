import XCTest

/// Sprint 19: fun themes, chosen in Settings › Appearance › Style.
final class ThemesUITests: XCTestCase {
    private static let themes = ["toyBox", "airplanes", "dinosaurs", "loveMom", "winter"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// A style is picked in Settings, brings the animations switch and takes over the accent color; Off undoes it.
    @MainActor
    func testStyleCanBeChosenAndTurnedOff() {
        let app = launchApp()
        openSettings(app)
        let style = app.buttons["settings.style"]
        XCTAssertTrue(scrollUntilExists(app, style), "Style picker missing")
        XCTAssertTrue(waitForRow(app, identifier: "settings.style", toRead: "Off"), "Style starts Off")
        XCTAssertFalse(app.switches["settings.themeAnimations"].exists, "No animations switch while Off")

        chooseStyle(app, "Toy Box")
        let animations = app.switches["settings.themeAnimations"]
        XCTAssertTrue(animations.waitForExistence(timeout: 5), "A style brings the Theme animations switch")
        // Choosing a style returns to Settings at the top; the accent row is further down.
        let accent = app.buttons["settings.accent"]
        XCTAssertTrue(scrollUntilExists(app, accent), "Accent row missing")
        XCTAssertFalse(accent.isEnabled, "The style sets the accent")
        captureScreen(app, named: "sprint19-settings-toyBox-light")
        app.tabBars.buttons["Dashboard"].tap()
        captureScreen(app, named: "sprint19-dashboard-after-choosing-light")

        app.tabBars.buttons["More"].tap()
        chooseStyle(app, "Off")
        XCTAssertFalse(animations.waitForExistence(timeout: 2), "Off hides the animations switch")
        XCTAssertTrue(scrollUntilExists(app, accent), "Accent row missing")
        XCTAssertTrue(accent.isEnabled, "Off gives the accent back")
    }

    @MainActor
    func testEveryThemeInLight() {
        tour(.light)
    }

    @MainActor
    func testEveryThemeInDark() {
        tour(.dark)
    }

    @MainActor
    func testEveryThemeAtTheLargestTextSize() {
        tour(.largeText)
    }

    /// Launches with each theme and keeps a screenshot of every tab that changes with it.
    @MainActor
    private func tour(_ variant: WalkVariant) {
        for theme in Self.themes {
            let app = launchApp(variant: variant, theme: theme)
            for tab in ["Dashboard", "Wishlist", "Tasks"] {
                let button = app.tabBars.buttons[tab]
                XCTAssertTrue(button.waitForExistence(timeout: 30), "\(theme): tab bar never appeared")
                button.tap()
                XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 10), "\(theme): \(tab) did not open")
                if theme == "airplanes", tab == "Tasks" {
                    let header = columnHeader(app, "Ready for takeoff")
                    XCTAssertTrue(header.waitForExistence(timeout: 5), "Airplanes renames To Do on the board")
                }
                captureScreen(app, named: "sprint19-\(theme)-\(tab.lowercased())-\(variant.rawValue)")
            }
            app.terminate()
        }
    }

    @MainActor
    private func chooseStyle(_ app: XCUIApplication, _ title: String) {
        let style = app.buttons["settings.style"]
        XCTAssertTrue(scrollUntilExists(app, style), "Style picker missing")
        style.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Style should offer '\(title)'")
        option.tap()
        XCTAssertTrue(waitForRow(app, identifier: "settings.style", toRead: title), "Style should read '\(title)'")
    }
}
