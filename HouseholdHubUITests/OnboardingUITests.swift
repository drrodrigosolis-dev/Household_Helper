import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstLaunchAsksForStartingBalanceThenShowsTheApp() {
        let app = launchApp(onboarded: false)
        let balance = app.textFields["onboarding.balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 10), "Onboarding sheet did not appear on first launch")
        captureScreen(app, named: "light-Onboarding")

        balance.tap()
        balance.typeText("1250.50")
        app.buttons["onboarding.start"].tap()

        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: balance)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Onboarding sheet should close")
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isHittable)
    }

    @MainActor
    func testInvalidBalanceShowsAnErrorAndKeepsTheSheetOpen() {
        let app = launchApp(onboarded: false)
        let balance = app.textFields["onboarding.balance"]
        XCTAssertTrue(balance.waitForExistence(timeout: 10))
        balance.tap()
        balance.typeText("lots")
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(balance.exists)
    }

    @MainActor
    func testWalkOnboardingInDarkAndLargeText() {
        for variant in [WalkVariant.dark, .largeText] {
            let app = launchApp(onboarded: false, variant: variant)
            XCTAssertTrue(app.textFields["onboarding.balance"].waitForExistence(timeout: 10))
            captureScreen(app, named: "\(variant.rawValue)-Onboarding")
            app.terminate()
        }
    }
}
