//
//  TadahUITests.swift
//  TadahUITests
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

final class TadahUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // PIN THE ORIENTATION. These tests inherit whatever rotation the simulator
        // was left in, and in landscape the Inbox lays out differently enough that
        // the guide flow's final assertion fails — a "failure" that is really just
        // the device being sideways. This is the likeliest explanation for the
        // flaky/failing UI runs reported in review.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testTabsNavigate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]   // skip the notif prompt; force English so selectors are language-independent
        app.launch()

        // To-Do is the launch tab. It's a TAB BAR BUTTON — the page masthead reads
        // "To-Dos & Reminders" since the clarity pass, so looking for a static text
        // "To-Do" matched nothing and this failed on the very first assertion.
        XCTAssertTrue(app.tabBars.buttons["To-Do"].waitForExistence(timeout: 5))

        // Add → the picker hero.
        app.tabBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Scan a document"].waitForExistence(timeout: 3))

        // Profile. The long inline "EXPLAIN DOCUMENTS IN" list this used to assert
        // on was replaced by a single Language row opening a sheet, so assert on
        // the screen's own masthead plus that row.
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["My Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 3))

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
        //
        // Matched by LABEL on any element, not as a StaticText: inbox rows became
        // buttons when swipe-to-complete landed, so the title is now a button's
        // accessibility label and the old staticTexts[…] lookup found nothing —
        // even though the item was right there on screen.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Prepare to file taxes"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
        }
    }

    // Tapping UPGRADE must never surface RevenueCat's raw "Error 23: There is an
    // issue with your configuration" alert. That fires whenever the store side
    // isn't ready (no Offering, no products, or a Simulator with no StoreKit
    // configuration) — which is precisely the state a tester's device is in today.
    // PaywallView checks for a usable offering first and shows a plain
    // "coming soon" screen instead.
    @MainActor
    func testUpgradeNeverShowsARawStoreError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["My Settings"].waitForExistence(timeout: 5))

        let upgrade = app.staticTexts["UPGRADE"]
        guard upgrade.waitForExistence(timeout: 3) else {
            throw XCTSkip("No UPGRADE row on this build — nothing to check.")
        }
        upgrade.tap()

        // Either the real paywall renders (StoreKit config / real Offering) or our
        // own coming-soon screen does. Assert a sheet actually OPENED before
        // checking for the absence of the error — otherwise this test could pass
        // simply by never getting there.
        let comingSoon = app.staticTexts["Tadah Plus is coming soon"]
        let closeButton = app.buttons["Close"]
        let opened = comingSoon.waitForExistence(timeout: 15)
            || closeButton.waitForExistence(timeout: 5)
        XCTAssertTrue(opened, "the upgrade sheet never appeared, so nothing was verified")

        // What must NOT appear is RevenueCat's developer-facing error.
        XCTAssertFalse(app.staticTexts["Error"].exists,
                       "RevenueCat's raw error alert reached the user")
        for fragment in ["issue with your configuration", "sdk-troubleshooting", "Error 23"] {
            XCTAssertEqual(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).count, 0,
                "Store-configuration internals leaked into the UI: \(fragment)")
        }

        // Attach what the user actually saw, so a future failure is diagnosable.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "upgrade-tapped"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // Rachel, 2026-08-13: "click task then edit then click add xx sometimes it's
    // not responding". The Add rows were bare Labels inside .plain Buttons — a
    // ~20pt-tall target with the padding OUTSIDE the button, so a tap a few points
    // off did nothing at all, and even a hit only produced an empty row whose
    // placeholder was too faint to notice. This drives the exact path she
    // described: open a task, Edit, then add one of each kind of row.
    //
    // Uses the taxes guide to get a real item into the inbox — the same
    // on-device, no-network flow testGuideFlowAddsItemToInbox already relies on.
    @MainActor
    func testEditingATaskCanAddStepsNotesAndDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        app.tabBars.buttons["Guides"].tap()
        let taxes = app.buttons["guide-taxes"]
        XCTAssertTrue(taxes.waitForExistence(timeout: 10))
        taxes.tap()
        app.buttons["A job (W-2)"].tap()
        app.buttons["Yes"].tap()
        let build = app.buttons["Build my checklist"]
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        build.tap()
        let addToInbox = app.buttons["Add to inbox"]
        XCTAssertTrue(addToInbox.waitForExistence(timeout: 10))
        addToInbox.tap()

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Prepare to file taxes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        // Count every editable row on the page — vertical-axis TextFields surface
        // as text VIEWS, single-line ones as text fields, so count both.
        func editableCount() -> Int { app.textFields.count + app.textViews.count }

        for button in ["Add a step", "Add a note", "Add a detail"] {
            let add = app.buttons[button].firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5), "\(button) is missing")
            let before = editableCount()
            add.tap()
            // A tap on the row must add a row. "Add a detail" adds a label AND a
            // value field, so assert growth rather than an exact count.
            var waited = 0.0
            while editableCount() <= before && waited < 3 { usleep(200_000); waited += 0.2 }
            XCTAssertGreaterThan(editableCount(), before, "\(button) did not add a row")
        }
    }

    // Rachel, 2026-08-13: "redo the current language change setting, it should
    // switch to everything not just explains, everything!" The picker used to
    // change only the AI's prose, leaving every button and heading in the phone's
    // language. Picking 中文 must now repaint the WHOLE app immediately — no
    // relaunch — so this asserts on the tab bar, which is as far from the AI's
    // output as the app gets.
    @MainActor
    func testLanguagePickerSwitchesTheWholeApp() throws {
        let app = XCUIApplication()
        // Phone stays in English on purpose: that's the user this is for — an
        // English phone, a reader who wants 中文.
        app.launchArguments = ["-uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["To-Do"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Profile"].tap()
        let languageRow = app.staticTexts["Language"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 5))
        languageRow.tap()

        // The rows are Buttons, so the script name is the button's a11y label,
        // not a separate StaticText.
        let chinese = app.buttons["中文"]
        XCTAssertTrue(chinese.waitForExistence(timeout: 5))
        chinese.tap()

        // The tab bar — never touched by the AI — must be Chinese now.
        XCTAssertTrue(app.tabBars.buttons["待办"].waitForExistence(timeout: 5),
                      "the app UI did not follow the language picker")
        XCTAssertFalse(app.tabBars.buttons["To-Do"].exists)

        // And back again, so the switch isn't one-way.
        app.tabBars.buttons["我的"].tap()
        let languageRowZh = app.staticTexts["语言"]
        XCTAssertTrue(languageRowZh.waitForExistence(timeout: 5))
        languageRowZh.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        english.tap()
        XCTAssertTrue(app.tabBars.buttons["To-Do"].waitForExistence(timeout: 5))
    }
}
