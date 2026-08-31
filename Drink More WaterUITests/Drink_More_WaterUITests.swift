import XCTest

final class Drink_More_WaterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsInitialExperience() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Drink More Water"].waitForExistence(timeout: 5)
            || app.tabBars.buttons["Home"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testPrimaryTabsExistAfterOnboarding() throws {
        let app = XCUIApplication()
        app.launch()

        if app.buttons["Get started"].waitForExistence(timeout: 2) {
            app.buttons["Get started"].tap()
        }

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Stats"].exists)
        XCTAssertTrue(app.tabBars.buttons["Setup"].exists)
        XCTAssertTrue(app.tabBars.buttons["About"].exists)
    }
}
