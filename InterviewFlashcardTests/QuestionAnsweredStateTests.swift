import SwiftData
import XCTest

final class QuestionAnsweredStateTests: XCTestCase {
    @MainActor
    func testQuestionWithoutAttemptsIsNotAnswered() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)

        XCTAssertFalse(card.hasBeenAnswered)
    }

    @MainActor
    func testQuestionWithSavedAttemptIsAnswered() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        try insertAttempt(status: .saved, for: card, context: context)

        XCTAssertTrue(card.hasBeenAnswered)
    }

    @MainActor
    func testQuestionWithFailedAttemptRemainsAnswered() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        try insertAttempt(status: .failed, for: card, context: context)

        XCTAssertTrue(card.hasBeenAnswered)
    }

    @MainActor
    private func insertAttempt(
        status: AttemptProcessingStatus,
        for card: QuestionCardRecord,
        context: ModelContext
    ) throws {
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: card.questionText,
            referenceAnswerTextSnapshot: "参考答案",
            referenceAnswerVersion: 1,
            rawText: "我的回答",
            inputMode: .typed,
            processingStatus: status,
            startedAt: Fixtures.now,
            submittedAt: Fixtures.now,
            question: card
        )
        context.insert(attempt)
        try context.save()
    }
}
