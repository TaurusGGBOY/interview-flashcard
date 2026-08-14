import XCTest

final class AnswerEditorTests: XCTestCase {
    func testCardBackHasNoNavigationTitle() {
        XCTAssertEqual(AnswerEditorView.navigationTitle(for: .cardBack), "")
    }

    func testStandaloneScreenKeepsAnswerNavigationTitle() {
        XCTAssertEqual(AnswerEditorView.navigationTitle(for: .screen), "回答")
    }

    func testSubmittedAttemptStillMapsBackToQuestion() {
        let questionID = UUID()
        XCTAssertEqual(
            AnswerEditorView.submittedQuestionID(questionID: questionID, attemptID: UUID()),
            questionID
        )
    }
}
