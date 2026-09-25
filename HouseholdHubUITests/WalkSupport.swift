import XCTest

/// Presentation variants every walked screen is captured in (sprint walk, household-sprint skill §4).
enum WalkVariant: String, CaseIterable {
    case light
    case dark
    case largeText
}

extension XCTestCase {
    /// Launches against an empty in-memory store; `onboarded` skips the first-launch sheet.
    @MainActor
    func launchApp(onboarded: Bool = true, variant: WalkVariant = .light) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-uiTesting"]
        if onboarded {
            arguments.append("-uiTestingSkipOnboarding")
        }
        if variant == .dark {
            arguments.append("-uiTestingDarkMode")
        }
        if variant == .largeText {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = arguments
        XCUIDevice.shared.appearance = variant == .dark ? .dark : .light
        app.launch()
        return app
    }

    /// Keeps a named screenshot in the result bundle; `Scripts/ui-test.sh` exports them for the walk review.
    @MainActor
    func captureScreen(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Records a transaction through the real Quick Add sheet.
    @MainActor
    func addViaQuickAdd(_ app: XCUIApplication, _ text: String) {
        app.buttons["quickadd.button"].tap()
        let field = app.textFields["quickadd.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Quick Add sheet did not open")
        field.tap()
        field.typeText(text)
        app.buttons["quickadd.save"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save '\(text)'")
    }

    @MainActor
    func transactionRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "transaction.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
