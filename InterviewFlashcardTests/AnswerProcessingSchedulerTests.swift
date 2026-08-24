import SwiftData
import XCTest

final class AnswerProcessingSchedulerTests: XCTestCase {
    @MainActor
    func testScheduledAttemptFinishesWithoutTheSubmittingView() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService(now: { Fixtures.now }).submitText(
            questionID: card.id,
            rawText: "先给出核心机制，再说明边界。",
            context: context
        )
        let processing = AnswerProcessingService(
            aiClient: RetryingAIClient(base: StubAIClient(), retryDelayNanoseconds: 0),
            now: { Fixtures.now }
        )
        let scheduler = AnswerProcessingScheduler(processing: processing, context: context)

        scheduler.schedule(attemptID: attempt.id)
        scheduler.schedule(attemptID: attempt.id)

        for _ in 0..<100 where attempt.processingStatus != .completed {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertEqual(attempt.evaluations.count, 1)
        XCTAssertFalse(scheduler.scheduledAttemptIDs.contains(attempt.id))
    }
}
