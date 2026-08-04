import Foundation
import SwiftData
import XCTest
@testable import InterviewFlashcard

final class HistoryQueryTests: XCTestCase {
    @MainActor
    func testGlobalHistoryIsNewestFirstFilterableAndHidesTrashedCards() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let first = try insertAttempt(card: card, at: Fixtures.now.addingTimeInterval(-100), context: context)
        let second = try insertAttempt(card: card, at: Fixtures.now, context: context)
        try context.save()

        let query = HistoryQuery(context: context)
        XCTAssertEqual(try query.global().map(\.id), [second.id, first.id])
        XCTAssertEqual(try query.global(topicID: card.topic.id).count, 2)

        card.trashedAt = Fixtures.now
        try context.save()
        XCTAssertTrue(try query.global().isEmpty)
    }

    @MainActor
    func testQuestionTimelineUsesAttemptSnapshots() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try insertAttempt(card: card, at: Fixtures.now, context: context)
        card.questionText = "后来修改的题干"
        try context.save()

        let result = try XCTUnwrap(HistoryQuery(context: context).forQuestion(card).first)
        XCTAssertEqual(result.id, attempt.id)
        XCTAssertNotEqual(result.questionTextSnapshot, card.questionText)
    }

    @MainActor
    private func insertAttempt(card: QuestionCardRecord, at date: Date, context: ModelContext) throws -> AnswerAttemptRecord {
        let answer = try XCTUnwrap(card.referenceAnswers.first)
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: card.questionText,
            referenceAnswerTextSnapshot: answer.answerText,
            referenceAnswerVersion: answer.version,
            rawText: "回答 \(date.timeIntervalSince1970)",
            inputMode: .typed,
            startedAt: date,
            submittedAt: date,
            question: card
        )
        context.insert(attempt)
        return attempt
    }
}
