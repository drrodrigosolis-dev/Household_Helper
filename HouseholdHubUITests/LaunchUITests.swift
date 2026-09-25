import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsRootTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["root.title"].waitForExistence(timeout: 10))
    }
}
