import XCTest

/// Smoke-walks every tab with a real vault (SCOUT_VAULT_PATH env) and
/// attaches a screenshot of each — catches runtime crashes and blank screens
/// that unit tests can't.
final class TabWalkUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWalkAllTabs() throws {
        let app = XCUIApplication()
        if let vaultPath = ProcessInfo.processInfo.environment["SCOUT_VAULT_PATH"] {
            app.launchEnvironment["SCOUT_VAULT_PATH"] = vaultPath
        }
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "tab bar should appear (vault override active)")

        for tab in ["Today", "Activity", "Proposals", "Knowledge", "Settings"] {
            let button = tabBar.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab) tab should exist")
            button.tap()
            sleep(2)
            attachShot(app, name: tab)
            XCTAssertTrue(app.state == .runningForeground, "app should stay alive on \(tab)")
        }

        // Drill into a run row if present (Sessions is the default Activity pane).
        tabBar.buttons["Activity"].tap()
        sleep(1)
        let runRow = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Morning briefing", "Consolidation", "Dreaming", "Research", "Weekend briefing"])
        ).firstMatch
        if runRow.waitForExistence(timeout: 3) {
            runRow.tap()
            sleep(2)
            attachShot(app, name: "RunDetail")
            XCTAssertTrue(app.state == .runningForeground, "app should stay alive on run detail")
            XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 5), "run detail should show Summary section")
        }
    }

    private func attachShot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
