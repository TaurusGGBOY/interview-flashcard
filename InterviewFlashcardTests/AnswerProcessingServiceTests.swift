import SwiftData
import XCTest
@testable import InterviewFlashcard

final class AnswerProcessingServiceTests: XCTestCase {
    @MainActor
    func testProcessingPersistsPolishAndSixScoresWithLocalTotal() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "值语义意味着复制后互不影响。",
            context: context
        )

        let evaluation = try await AnswerProcessingService(aiClient: RetryingAIClient(base: StubAIClient(), retryDelayNanoseconds: 0))
            .process(attemptID: attempt.id, context: context)

        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertEqual(attempt.polishResults.count, 1)
        XCTAssertEqual(attempt.evaluations.count, 1)
        XCTAssertEqual(evaluation.totalScore, 75)
        XCTAssertEqual(evaluation.dimensionScores, DimensionScores(correctness: 80, coverage: 60, reasoning: 80, structure: 80, tradeoffs: 70, precision: 100))
    }

    @MainActor
    func testProcessingFailureKeepsAttemptAndAllowsExplicitRetry() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(questionID: card.id, rawText: "回答", context: context)

        let paused = AnswerProcessingService(aiClient: StubAIClient(mode: .processingPaused))
        await XCTAssertThrowsErrorAsync({ try await paused.process(attemptID: attempt.id, context: context) })
        XCTAssertEqual(attempt.processingStatus, .failed)
        XCTAssertEqual(attempt.evaluations.count, 0)

        _ = try await AnswerProcessingService(aiClient: StubAIClient()).process(attemptID: attempt.id, context: context)
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertEqual(attempt.evaluations.count, 1)
        XCTAssertGreaterThanOrEqual(attempt.polishResults.count, 1)
    }

    @MainActor
    func testInvalidEvaluationIsRejectedWithoutPersistingEvaluation() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(questionID: card.id, rawText: "回答", context: context)
        let invalid = AnswerProcessingService(aiClient: StubAIClient(mode: .evaluationInvalid))

        await XCTAssertThrowsErrorAsync({ try await invalid.process(attemptID: attempt.id, context: context) })
        XCTAssertEqual(attempt.processingStatus, .failed)
        XCTAssertTrue(attempt.evaluations.isEmpty)
        XCTAssertNotNil(attempt.failureSummary)
    }
}
