import XCTest

/// Sprint 16: the app in Spanish (owner decision 25). Checks the String Catalog is compiled in (tab titles are
/// Spanish) and captures every tab, Settings and Quick Add in light and at the largest text size, so the walk can
/// spot clipped or untranslated text. Navigates by identifiers and Spanish titles only.
final class SpanishWalkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private let tabs = ["Inicio", "Presupuesto", "Deseos", "Tareas", "Más"]

    @MainActor
    func testEveryTabInSpanish() {
        for variant in [WalkVariant.light, .largeText] {
            let app = launchApp(variant: variant, language: "es")
            let budget = app.tabBars.buttons["Presupuesto"]
            XCTAssertTrue(budget.waitForExistence(timeout: 30), "Tab titles should be Spanish")
            for tab in tabs {
                app.tabBars.buttons[tab].tap()
                captureScreen(app, named: "sprint16-es-\(tab)-\(variant.rawValue)")
            }
            let settings = app.buttons["Configuración"]
            XCTAssertTrue(settings.waitForExistence(timeout: 10), "More should list Configuración")
            settings.tap()
            XCTAssertTrue(app.navigationBars["Configuración"].waitForExistence(timeout: 10))
            captureScreen(app, named: "sprint16-es-configuracion-\(variant.rawValue)")
            app.tabBars.buttons["Inicio"].tap()
            openQuickAdd(app)
            captureScreen(app, named: "sprint16-es-registro-rapido-\(variant.rawValue)")
            app.terminate()
        }
    }
}
