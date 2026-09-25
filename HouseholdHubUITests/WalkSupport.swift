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
}
