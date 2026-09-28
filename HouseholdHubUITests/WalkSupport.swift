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
    /// - Parameter language: an app language such as "es" (Sprint 16 walk); formats still follow the region.
    /// - Parameter theme: a Sprint 19 style's stored name, such as "toyBox".
    /// - Parameter tips: Sprint 24 — forces every contextual tip on, from a freshly reset datastore
    ///   (`-uiTestingTips`), for `Sprint24TipsUITests`. Every other walk leaves this false, so tips stay hidden and
    ///   never cover a control mid-test.
    /// - Parameter extraArguments: more launch arguments, such as Sprint 24's `-uiTestingTour`.
    func launchApp(
        onboarded: Bool = true, variant: WalkVariant = .light, language: String? = nil, theme: String? = nil,
        tips: Bool = false, extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-uiTesting"]
        if tips {
            arguments.append("-uiTestingTips")
        }
        if let theme {
            arguments += ["-funTheme", theme]
        }
        if onboarded {
            arguments.append("-uiTestingSkipOnboarding")
        }
        if variant == .dark {
            arguments.append("-uiTestingDarkMode")
        }
        if variant == .largeText {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if let language {
            arguments += ["-AppleLanguages", "(\(language))"]
        }
        arguments += extraArguments
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

    /// Scrolls up until `element` exists. Lists create rows lazily, so at the largest text sizes a section below the
    /// first screen isn't in the accessibility tree until scrolled to (run 36211055316).
    ///
    /// Stops only once the element is on screen, swiping slowly toward it: a fast swipe keeps coasting after the
    /// element appears and carries it off the top of a lazy list again (run 36435820743: the editor's split row was
    /// found, then gone a second later). On screen means hittable, or, for text that isn't a control (a `Label` row
    /// can report not hittable while plainly visible, L-027's split info), inside the window.
    @MainActor
    func scrollUntilExists(_ app: XCUIApplication, _ query: XCUIElement, maxSwipes: Int = 8) -> Bool {
        // Position and hittability need one element; a query can match several (run 36453971771).
        let element = query.firstMatch
        let onScreen = {
            element.isHittable || (app.windows.firstMatch.frame.contains(element.frame) && !element.frame.isEmpty)
        }
        for _ in 0..<maxSwipes {
            if element.waitForExistence(timeout: 2), onScreen() {
                return true
            }
            // Loaded but off screen: it sits above the middle once the list scrolled past it.
            if element.exists, element.frame.midY < app.frame.midY {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        return element.waitForExistence(timeout: 5) && onScreen()
    }

    /// Records a transaction through the real Quick Add sheet.
    @MainActor
    func addViaQuickAdd(_ app: XCUIApplication, _ text: String) {
        let field = openQuickAdd(app)
        typeIntoQuickAdd(field, text)
        tapQuickAddSave(app)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Quick Add did not save '\(text)'")
    }

    /// Types into Quick Add and waits until the field holds all of it. On a slow simulator the app can receive the
    /// keystrokes seconds after `typeText` returns (run 36326496000: an AutoFill prompt after "+" held back the rest of
    /// "+ 1200 paycheck"), and a partial "+ 1" would already parse as an amount. Run 36362839424 (large text) needed
    /// more than 10 s on a runner taking ~5 s per element lookup; the failure now says what the field did hold.
    @MainActor
    func typeIntoQuickAdd(_ field: XCUIElement, _ text: String) {
        field.tap()
        field.typeText(text)
        let holds = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        let result = XCTWaiter().wait(for: [holds], timeout: 20)
        XCTAssertEqual(result, .completed, "Quick Add never showed '\(text)'; it holds '\(field.value ?? "nil")'")
    }

    /// Taps Save once it is enabled: a tap on the disabled button does nothing and the sheet stays open.
    @MainActor
    func tapQuickAddSave(_ app: XCUIApplication) {
        let save = app.buttons["quickadd.save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 10), .completed, "Quick Add Save stayed disabled")
        save.tap()
    }

    /// Replaces a text field's contents. Taps at the trailing edge so the cursor lands after the existing text:
    /// fields inside `LabeledContent` are narrow and trailing-aligned, so a center tap can land mid-value.
    /// The field's value is read back with a wait: on a slow simulator the accessibility value can lag the typing
    /// (run 36211558237 read the old "20"). One more edit is made only if the field still doesn't hold the text.
    @MainActor
    func replaceText(in field: XCUIElement, with text: String) {
        for _ in 0..<2 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            let current = (field.value as? String) ?? ""
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2)
            field.typeText(deletes + text)
            let holds = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
            if XCTWaiter().wait(for: [holds], timeout: 5) == .completed {
                return
            }
        }
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

    /// Swipes `row` until its swipe action `action` shows. A synthesized swipe is sometimes lost on a busy simulator:
    /// run 36342742016 swiped a Budget row and no Delete appeared, on code that passed on the run before. One more
    /// swipe is made only if the action never showed; the action must still be offered.
    @MainActor
    @discardableResult
    func revealSwipeAction(_ row: XCUIElement, _ action: XCUIElement, leading: Bool = false) -> Bool {
        for _ in 0..<2 {
            if leading { row.swipeRight() } else { row.swipeLeft() }
            if action.waitForExistence(timeout: 4) {
                return true
            }
        }
        XCTFail("Swiping the row never offered \(action)")
        return false
    }

    /// Taps a sheet's Save and waits for the sheet to close. Run 36342742016 kept the Recurring editor open after
    /// its Save tap: the UI hierarchy at failure showed the editor, Save enabled, the typed amount, and no error, so
    /// the synthesized tap never arrived. The tap is repeated once only in that state (Save guards double saves).
    @MainActor
    func tapSaveAndWaitForClose(_ save: XCUIElement, closes screen: XCUIElement) {
        for _ in 0..<2 {
            save.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: screen)
            if XCTWaiter().wait(for: [gone], timeout: 5) == .completed {
                return
            }
            if !save.exists || !save.isEnabled {
                break
            }
        }
        XCTFail("Save did not close the screen")
    }

    @MainActor
    func transactionRow(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "transaction.row")
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
