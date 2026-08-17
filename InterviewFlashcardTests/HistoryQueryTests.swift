import Foundation
import SwiftData
import XCTest

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
    func testSearchMatchesQuestionAnswerAndTopicButNotTrashedQuestions() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, question: "如何设计缓存失效？")
        card.topic.name = "后端系统"
        let attempt = try insertAttempt(card: card, at: Fixtures.now, context: context)
        attempt.rawText = "使用 Cache Key 和主动失效。"
        try context.save()

        XCTAssertTrue(HistoryQuery.matches(attempt, query: "缓存失效"))
        XCTAssertTrue(HistoryQuery.matches(attempt, query: "主动失效"))
        XCTAssertTrue(HistoryQuery.matches(attempt, query: "后端系统"))
        XCTAssertTrue(HistoryQuery.matches(attempt, query: "cache key"))
        XCTAssertTrue(HistoryQuery.matches(attempt, query: ""))

        card.trashedAt = Fixtures.now
        try context.save()
        XCTAssertFalse(try HistoryQuery(context: context).global().contains(where: { $0.id == attempt.id }))
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
