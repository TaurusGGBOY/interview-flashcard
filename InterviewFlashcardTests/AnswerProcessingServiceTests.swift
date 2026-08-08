import SwiftData
import XCTest

final class AnswerProcessingServiceTests: XCTestCase {
    @MainActor
    func testProcessingPersistsOneEvaluationAndSixScoresWithLocalTotal() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "值语义意味着复制后互不影响。",
            context: context
        )

        let client = RecordingAIClient()
        let evaluation = try await AnswerProcessingService(aiClient: client)
            .process(attemptID: attempt.id, context: context)

        let polishCallCount = await client.polishCallCount()
        let evaluateCallCount = await client.evaluateCallCount()
        let recordedRequest = await client.lastEvaluationRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(polishCallCount, 0)
        XCTAssertEqual(evaluateCallCount, 1)
        XCTAssertEqual(request.rawText, request.polishedText)
        XCTAssertTrue(request.introducedClaims.isEmpty)
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertTrue(attempt.polishResults.isEmpty)
        XCTAssertEqual(attempt.evaluations.count, 1)
        XCTAssertNil(evaluation.polishResultID)
        XCTAssertEqual(evaluation.totalScore, 75)
        XCTAssertEqual(evaluation.dimensionScores, DimensionScores(correctness: 80, coverage: 60, reasoning: 80, structure: 80, tradeoffs: 70, precision: 100))
        let detail = try JSONDecoder().decode(
            EvaluationDetailPayload.self,
            from: Data(evaluation.feedbackJSON.utf8)
        )
        XCTAssertEqual(detail.schemaVersion, 2)
        XCTAssertEqual(detail.dimensions.count, 6)
        XCTAssertFalse(detail.gaps.isEmpty)
        XCTAssertEqual(request.rubric.version, EvaluationRubric.seniorSoftwareEngineer.version)
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
        XCTAssertTrue(attempt.polishResults.isEmpty)
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
        XCTAssertTrue(attempt.polishResults.isEmpty)
    }
}

private actor RecordingAIClient: AIClient {
    private let base = StubAIClient()
    private var polishCalls = 0
    private var evaluateCalls = 0
    private var evaluationRequest: EvaluationRequest?

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await base.decompose(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        polishCalls += 1
        return try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        evaluateCalls += 1
        evaluationRequest = request
        return try await base.evaluate(request)
    }

    func polishCallCount() -> Int { polishCalls }
    func evaluateCallCount() -> Int { evaluateCalls }
    func lastEvaluationRequest() -> EvaluationRequest? { evaluationRequest }
}
