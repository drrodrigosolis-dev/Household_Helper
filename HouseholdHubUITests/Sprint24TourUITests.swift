import XCTest

/// Sprint 24: the first-run tour, walked stop by stop with a screenshot of each, so a layout change that breaks a stop
/// fails CI. Other UI tests never see the tour: it needs `-uiTestingTour` under `-uiTesting`.
final class Sprint24TourUITests: XCTestCase {
    private static let tour = ["-uiTestingTour"]
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// The tab showing under each stop, as the callout reports it (its step's accessibility value under UI tests).
    private static let screens = ["dashboard", "dashboard", "budget", "wishlist", "tasks", "more"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// Started from the Dashboard's offer (an install already set up), all six stops in turn, then Done.
    @MainActor
    func testTourWalksAllSixStops() {
        let app = launchApp(extraArguments: Self.tour)
        startFromOffer(app)
        walkTour(app, variant: "light")
    }

    /// The same walk in dark mode at the largest text size: the callout docks at the bottom and never truncates.
    @MainActor
    func testTourInDarkModeAtLargeText() {
        let app = launchApp(variant: .dark, extraArguments: Self.tour + Self.largeText)
        startFromOffer(app)
        walkTour(app, variant: "dark-largeText")
    }

    /// Skip ends the tour at once; the app underneath works again and the offer doesn't come back.
    @MainActor
    func testSkipEndsTheTour() {
        let app = launchApp(extraArguments: Self.tour)
        startFromOffer(app)
        assertStop(app, 1)
        app.buttons["tour.skip"].tap()
        XCTAssertTrue(waitUntilGone(callout(app)), "Skip tour should end the tour")
        XCTAssertFalse(app.descendants(matching: .any)["tour.offer"].exists, "The offer is gone after the tour")
        app.tabBars.buttons["Budget"].tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 10), "The app is usable after Skip")
    }

    /// Not now dismisses the offer without starting the tour.
    @MainActor
    func testNotNowDismissesTheOffer() {
        let app = launchApp(extraArguments: Self.tour)
        let dismiss = app.buttons["tour.offer.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 30), "The Dashboard should offer the tour")
        captureScreen(app, named: "sprint24-tour-offer-light")
        dismiss.tap()
        XCTAssertTrue(waitUntilGone(app.descendants(matching: .any)["tour.offer"]), "Not now hides the offer")
        XCTAssertFalse(callout(app).exists, "Not now doesn't start the tour")
    }

    /// Settings › Show the Tour Again restarts the tour at its first stop, on the Dashboard.
    @MainActor
    func testSettingsShowsTheTourAgain() {
        let app = launchApp(extraArguments: Self.tour)
        let dismiss = app.buttons["tour.offer.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 30), "The Dashboard should offer the tour")
        dismiss.tap()
        openSettings(app)
        let replay = app.buttons["settings.showTour"]
        XCTAssertTrue(scrollUntilExists(app, replay), "Settings should have Show the Tour Again")
        captureScreen(app, named: "sprint24-settings-tutorial-light")
        replay.tap()
        assertStop(app, 1)
        captureScreen(app, named: "sprint24-tour-replayed-light")
        app.buttons["tour.next"].tap()
        assertStop(app, 2)
    }

    /// Without `-uiTestingTour`, UI tests never see the tour or its offer.
    @MainActor
    func testOtherUITestsNeverSeeTheTour() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 30), "Tab bar never appeared")
        XCTAssertTrue(app.buttons["quickadd.button"].waitForExistence(timeout: 10), "Dashboard never appeared")
        XCTAssertFalse(app.descendants(matching: .any)["tour.offer"].exists, "No offer under -uiTesting")
        XCTAssertFalse(callout(app).exists, "No tour under -uiTesting")
    }

    // MARK: Helpers

    @MainActor
    private func callout(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["tour.callout"]
    }

    @MainActor
    private func startFromOffer(_ app: XCUIApplication) {
        let start = app.buttons["tour.offer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "The Dashboard should offer the tour")
        start.tap()
    }

    @MainActor
    private func walkTour(_ app: XCUIApplication, variant: String) {
        for stop in 1...Self.screens.count {
            assertStop(app, stop)
            captureScreen(app, named: "sprint24-tour-\(stop)-\(Self.screens[stop - 1])-\(variant)")
            app.buttons["tour.next"].tap()
        }
        XCTAssertTrue(waitUntilGone(callout(app)), "Done should end the tour")
    }

    /// The callout shows stop `stop` of six, with Next (Done on the last) and Skip, over the right tab.
    @MainActor
    private func assertStop(_ app: XCUIApplication, _ stop: Int) {
        let card = callout(app)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Stop \(stop): no callout")
        let step = app.descendants(matching: .any)["tour.step"]
        let count = "\(stop) of \(Self.screens.count)"
        let counted = becomes(NSPredicate(format: "label CONTAINS %@", count), on: step)
        XCTAssertTrue(counted, "Stop \(stop): the callout reads '\(step.label)', not '\(count)'")
        let screen = Self.screens[stop - 1]
        let shown = becomes(NSPredicate(format: "value == %@", screen), on: step)
        XCTAssertTrue(shown, "Stop \(stop): expected \(screen), showing \(String(describing: step.value))")
        let next = app.buttons["tour.next"]
        XCTAssertTrue(next.exists, "Stop \(stop): no Next")
        XCTAssertEqual(next.label, stop == Self.screens.count ? "Done" : "Next", "Stop \(stop): Next's title")
        XCTAssertTrue(app.buttons["tour.skip"].exists, "Stop \(stop): Skip tour should always be there")
    }

    @MainActor
    private func becomes(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) -> Bool {
        becomes(NSPredicate(format: "exists == false"), on: element)
    }
}
