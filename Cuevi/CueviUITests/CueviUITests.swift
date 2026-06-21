//
//  CueviUITests.swift
//  CueviUITests
//
//  Tap-through tests for the core navigation and the guide → Review → Add flow.
//  These catch silent breakage in the screens/wiring that the logic unit tests
//  can't see (the unit tests cover pure model logic; these drive the real UI).
//
//  The guide flow deliberately uses "taxes" — a SENSITIVE guide, so the AI
//  polish pass is skipped and the checklist builds fully on-device. That keeps
//  the test fast and deterministic (no network).
//

import XCTest

final class CueviUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsNavigate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]   // skip the notif prompt; force English so selectors are language-independent
        app.launch()

        // Inbox is the launch tab.
        XCTAssertTrue(app.staticTexts["Inbox"].waitForExistence(timeout: 5))

        // Add → the picker hero.
        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Scan a document"].waitForExistence(timeout: 3))

        // Profile → the wired language picker.
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["EXPLAIN DOCUMENTS IN"].waitForExistence(timeout: 3))

        // Guides → the library.
        app.tabBars.buttons["Guides"].tap()
        XCTAssertTrue(app.buttons["guide-taxes"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testGuideFlowAddsItemToInbox() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]   // skip the notif prompt; force English so selectors are language-independent
        app.launch()

        // Open the Taxes guide (sensitive → built on-device, no network).
        app.tabBars.buttons["Guides"].tap()
        let taxes = app.buttons["guide-taxes"]
        XCTAssertTrue(taxes.waitForExistence(timeout: 5))
        taxes.tap()

        // Answer the two required choice questions (unique option labels).
        app.buttons["A job (W-2)"].tap()
        app.buttons["Yes"].tap()

        // Build the checklist → the shared Review screen.
        let build = app.buttons["Build my checklist"]
        XCTAssertTrue(build.waitForExistence(timeout: 3))
        build.tap()

        // Review loaded; confirm into the inbox.
        let add = app.buttons["Add to inbox"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))   // allow the brief build/loading phase
        add.tap()

        // Lands back in the Inbox with the new guide-tagged item.
        XCTAssertTrue(app.staticTexts["Prepare to file taxes"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
        }
    }
}
