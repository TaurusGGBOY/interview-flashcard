import XCTest

@MainActor
final class LibraryAnsweredIndicatorUITests: XCTestCase {
    func testAnsweredIndicatorAppearsInLibrarySearchAndHidesDuringSelection() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        let libraryTab = app.tabBars.buttons["题库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5))
        libraryTab.tap()

        let backendTopic = app.buttons[
            "library.topic.00000001-0000-0000-0000-000000000001"
        ]
        XCTAssertTrue(backendTopic.waitForExistence(timeout: 5))
        backendTopic.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)
        ).tap()

        let answeredQuestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "验收题目 1")
        ).firstMatch
        let unansweredQuestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "验收题目 2")
        ).firstMatch

        XCTAssertTrue(answeredQuestion.waitForExistence(timeout: 5))
        XCTAssertTrue(answeredQuestion.label.contains("已回答"))
        XCTAssertTrue(unansweredQuestion.waitForExistence(timeout: 5))
        XCTAssertFalse(unansweredQuestion.label.contains("已回答"))
        addScreenshot(named: "library-expanded", app: app)

        app.swipeDown()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("验收题目 1")

        XCTAssertTrue(answeredQuestion.waitForExistence(timeout: 5))
        XCTAssertTrue(answeredQuestion.label.contains("已回答"))
        XCTAssertFalse(unansweredQuestion.exists)
        addScreenshot(named: "library-search", app: app)

        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(answeredQuestion.waitForExistence(timeout: 5))

        answeredQuestion.press(forDuration: 0.7)

        let selectedQuestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "选择题目：验收题目 1")
        ).firstMatch
        XCTAssertTrue(selectedQuestion.waitForExistence(timeout: 5))
        XCTAssertFalse(selectedQuestion.label.contains("已回答"))
        addScreenshot(named: "library-selection", app: app)
    }

    private func addScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
