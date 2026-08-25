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
        XCTAssertTrue(app.staticTexts["六维具体详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["做得好的地方"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["做得不好的地方"].waitForExistence(timeout: 5))
        let rescore = app.buttons["answer-editor.result.rescore"]
        XCTAssertTrue(rescore.waitForExistence(timeout: 5))
        rescore.tap()
        XCTAssertTrue(
            app.staticTexts["answer-editor.result.score"].waitForExistence(timeout: 10),
            "点击重新评分后应重新显示评分结果"
        )
        XCTAssertTrue(
            app.buttons["answer-editor.result.rescore"].waitForExistence(timeout: 10),
            "点击重新评分后结果页应保持可操作"
        )
        XCTAssertFalse(app.staticTexts["原回答证据"].exists)
        XCTAssertFalse(app.staticTexts["本题缺口"].exists)
    }

    func testRescoreShowsInProgressStateBeforeRefreshingResult() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFStubMode", "processing-delayed",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["practice.answer"].waitForExistence(timeout: 5))
        app.buttons["practice.answer"].tap()
        let editor = app.textViews["answer-editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("先给出核心机制，再说明边界条件和取舍。")
        app.buttons["answer-editor.submit.keyboard"].tap()

        let rescore = app.buttons["answer-editor.result.rescore"]
        XCTAssertTrue(rescore.waitForExistence(timeout: 10))
        rescore.tap()

        XCTAssertTrue(rescore.waitForExistence(timeout: 2))
        XCTAssertTrue(rescore.label.contains("正在重新评分"))
        XCTAssertFalse(rescore.isEnabled)
        XCTAssertTrue(app.staticTexts["answer-editor.result.score"].waitForExistence(timeout: 10))
        let refreshedRescore = app.buttons["answer-editor.result.rescore"]
        XCTAssertTrue(refreshedRescore.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: refreshedRescore
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
    }

    func testNextQuestionWorksWhileBackgroundScoring() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFStubMode", "processing-delayed",
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
        app.buttons["answer-editor.submit.keyboard"].tap()

        let next = app.buttons["answer-editor.next-while-processing"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        XCTAssertTrue(app.buttons["practice.answer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["answer-editor.text"].exists)
        XCTAssertFalse(app.otherElements["answer-editor.result"].waitForExistence(timeout: 1))
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

    func testCardCanBeDeletedUndoneAndImmediatelyAdvanced() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "reclassification-103",
            "-IFRandomSeed", "42",
        ]
        app.launch()

        let card = app.otherElements["practice.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let question = app.staticTexts["practice.question"]
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        let originalQuestion = question.label
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '题号 '")).firstMatch.exists
        )

        card.swipeUp()

        let undo = app.buttons["practice.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertEqual(question.label, originalQuestion)

        app.buttons["practice.skip"].tap()

        let nextQuestion = app.staticTexts
            .matching(identifier: "practice.question")
            .matching(NSPredicate(format: "label != %@", originalQuestion))
            .firstMatch
        XCTAssertTrue(
            nextQuestion.waitForExistence(timeout: 1),
            "撤销删除后点击下一题应立即消费已预取的卡片"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '题号 '")).firstMatch.exists
        )
    }

}
