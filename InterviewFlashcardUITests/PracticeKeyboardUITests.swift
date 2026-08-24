import XCTest

final class PracticeKeyboardUITests: XCTestCase {
    func testAnswerCanBeSubmittedFromKeyboardToolbar() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        let startAnswer = app.buttons["practice.answer"]
        XCTAssertTrue(startAnswer.waitForExistence(timeout: 5))
        startAnswer.tap()

        let editor = app.textViews["answer-editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("这是一个用于验证键盘提交按钮的回答。")

        let keyboardSubmit = app.buttons["answer-editor.submit.keyboard"]
        XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardSubmit.isEnabled)
        keyboardSubmit.tap()

        // The tap itself is the behavior under test. Submission clears the
        // editor immediately before asynchronous scoring starts; this avoids
        // coupling the UI test to the later evaluation/network pipeline.
        XCTAssertTrue(
            NSPredicate(format: "value == ''").evaluate(with: editor)
                || !editor.exists
        )
    }

    func testSubmittedAnswerShowsScoreWhileAnswerPageRemainsOpen() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        let startAnswer = app.buttons["practice.answer"]
        XCTAssertTrue(startAnswer.waitForExistence(timeout: 5))
        startAnswer.tap()

        let editor = app.textViews["answer-editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("先给出核心机制，再说明边界条件和取舍。")

        let keyboardSubmit = app.buttons["answer-editor.submit.keyboard"]
        XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 5))
        keyboardSubmit.tap()

        let score = app.staticTexts["answer-editor.result.score"]
        XCTAssertTrue(score.waitForExistence(timeout: 5))
    }

    func testReturningFromAnswerThenSkippingAdvancesCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        let answerButton = app.buttons["practice.answer"]
        XCTAssertTrue(answerButton.waitForExistence(timeout: 5))
        answerButton.tap()

        let editor = app.textViews["answer-editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let returnButton = app.buttons["practice.return-to-question"]
        XCTAssertTrue(returnButton.waitForExistence(timeout: 5))
        returnButton.tap()

        let skipButton = app.buttons["practice.skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertTrue(app.buttons["practice.answer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["answer-editor.text"].exists)
    }

    func testCardCanBeDeletedBySwipingUpAndUndone() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        let card = app.otherElements["practice.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let question = app.staticTexts["practice.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        let originalQuestion = question.label

        card.swipeUp()

        let undo = app.buttons["practice.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertEqual(question.label, originalQuestion)
    }

}
