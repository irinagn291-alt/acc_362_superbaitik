import XCTest

final class DiaryJourneyTests: XCTestCase {
    func testFirstEntrySurvivesRelaunchAndCanBeEditedAndRemoved() {
        let app = XCUIApplication()
        app.launchEnvironment["LEPESTOK_TEST_JOURNAL"] = UUID().uuidString
        app.launch()
        let record = app.buttons["today.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 6))
        record.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Day 1"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Day 1"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Calendar"].tap()
        app.buttons["calendar.edit"].tap()
        let ended = app.switches["Period has ended"].firstMatch
        ended.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Save"].tap()

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Since your period started"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Insights"].tap()
        app.buttons["Period length"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "1 finished period")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Journal"].tap()
        app.buttons["history.entry"].tap()
        app.buttons["Delete entry"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Your first entry"].waitForExistence(timeout: 5))
    }

    func testDailyCheckInAndPrivacyPolicy() {
        let app = XCUIApplication()
        app.launchEnvironment["LEPESTOK_TEST_JOURNAL"] = UUID().uuidString
        app.launch()
        app.buttons["today.guide"].tap()
        XCTAssertTrue(app.navigationBars["Journal guide"].exists)
        app.buttons["Done"].tap()
        app.buttons["today.privacy"].tap()
        XCTAssertTrue(app.staticTexts["Where entries go"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        let checkIn = app.buttons["today.checkIn"]
        if !checkIn.isHittable { app.swipeUp() }
        checkIn.tap()
        app.buttons["checkin.energy"].tap()
        app.buttons["Usual"].tap()
        app.buttons["checkin.save"].tap()

        app.terminate()
        app.launch()
        if !checkIn.isHittable { app.swipeUp() }
        checkIn.tap()
        XCTAssertTrue(app.buttons["Delete this check-in"].waitForExistence(timeout: 5))
        app.buttons["Delete this check-in"].tap()
        app.buttons["Delete check-in"].tap()
        XCTAssertTrue(app.staticTexts["Your saved check-ins will appear here."].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
    }
}
