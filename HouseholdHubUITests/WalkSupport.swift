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

    /// Opens the Quick Add sheet and returns its text field. Waits for the button first: a cold simulator launch can
    /// keep the first frame blank for 20 s or more (run 36209505191). If the sheet hasn't appeared shortly after the
    /// tap, taps once more; that is safe because a second tap only happens while no sheet is showing.
    @MainActor
    @discardableResult
    func openQuickAdd(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["quickadd.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "Quick Add button never appeared")
        button.tap()
        let field = app.textFields["quickadd.text"]
        if !field.waitForExistence(timeout: 3), button.isHittable {
            button.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Quick Add sheet did not open")
        return field
    }

    /// Records a transaction through the real Quick Add sheet.
    @MainActor
    func addViaQuickAdd(_ app: XCUIApplication, _ text: String) {
        let field = openQuickAdd(app)
        field.tap()
        field.typeText(text)
        app.buttons["quickadd.save"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save '\(text)'")
    }

    /// Replaces a text field's contents. Taps at the trailing edge so the cursor lands after the existing text:
    /// fields inside `LabeledContent` are narrow and trailing-aligned, so a center tap can land mid-value.
    @MainActor
    func replaceText(in field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2)
        field.typeText(deletes + text)
        XCTAssertEqual(field.value as? String, text, "Field did not end up holding '\(text)'")
    }

    /// Focuses a text field, then types. At accessibility text sizes a `LabeledContent` row stacks its label above
    /// the field, so a center tap can land on the label; try a few points inside the row until the field has focus.
    @MainActor
    func focusAndType(_ field: XCUIElement, _ text: String) {
        let points = [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.9, dy: 0.8), CGVector(dx: 0.5, dy: 0.85)]
        for point in points {
            field.coordinate(withNormalizedOffset: point).tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                break
            }
        }
        field.typeText(text)
    }

    /// Waits for a detail row (label plus value, exposed as one element) to read `text`.
    @MainActor
    func waitForRow(_ app: XCUIApplication, identifier: String, toRead text: String) -> Bool {
        let row = app.descendants(matching: .any)[identifier]
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: row)
        return XCTWaiter().wait(for: [expectation], timeout: 10) == .completed
    }

    @MainActor
    func transactionRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "transaction.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
