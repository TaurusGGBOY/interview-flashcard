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
    func testForceRescoreCreatesNewEvaluationForSameAttempt() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "回答",
            context: context
        )
        let client = RecordingAIClient()
        let service = AnswerProcessingService(aiClient: client)

        let first = try await service.score(attemptID: attempt.id, context: context)
        let reused = try await service.score(attemptID: attempt.id, context: context)
        let rescored = try await service.score(
            attemptID: attempt.id,
            context: context,
            forceRescore: true
        )

        XCTAssertEqual(first.id, reused.id)
        XCTAssertNotEqual(first.id, rescored.id)
        XCTAssertEqual(attempt.evaluations.count, 2)
        let evaluateCallCount = await client.evaluateCallCount()
        XCTAssertEqual(evaluateCallCount, 2)
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

    @MainActor
    func testReferenceAnswerIsGeneratedLazilyAndPersistedOnce() async throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let topic = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )
        let source = SourceDocumentRecord(
            fileName: "lazy.md",
            contentHash: "lazy",
            importerVersion: "test",
            importedAt: Fixtures.now
        )
        let card = QuestionCardRecord(
            questionText: "Kubernetes 控制器如何让实际状态收敛到期望状态？",
            sourceAnchor: "lazy.md#controller",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now,
            activatedAt: Fixtures.now,
            topic: topic,
            sourceDocument: source
        )
        context.insert(source)
        context.insert(card)
        try context.save()

        let client = RecordingAIClient()
        let service = ReferenceAnswerService(
            aiClient: client,
            now: { Fixtures.now }
        )
        let first = try await service.ensureReferenceAnswer(questionID: card.id, context: context)
        let second = try await service.ensureReferenceAnswer(questionID: card.id, context: context)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.origin, .aiGenerated)
        XCTAssertEqual(first.promptVersion, PromptCatalog.referenceAnswerVersion)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 1)
        let referenceAnswerCallCount = await client.referenceAnswerCallCount()
        let referenceAnswerRequest = await client.lastReferenceAnswerRequest()
        XCTAssertEqual(referenceAnswerCallCount, 1)
        XCTAssertEqual(referenceAnswerRequest?.question, card.questionText)
    }

    @MainActor
    func testStagedProcessingPersistsScoreBeforeFeedbackAndReferenceAnswer() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, includeReferenceAnswer: false)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "值语义意味着复制后互不影响。",
            context: context
        )
        let client = StagedRecordingAIClient()
        let service = AnswerProcessingService(aiClient: client)

        let evaluation = try await service.score(attemptID: attempt.id, context: context)
        XCTAssertEqual(evaluation.status, .feedback)
        XCTAssertEqual(attempt.processingStatus, .feedback)
        XCTAssertEqual(evaluation.totalScore, 75)
        var calls = await client.calls()
        XCTAssertEqual(calls, ["score"])

        try await service.completeFeedback(
            attemptID: attempt.id,
            evaluationID: evaluation.id,
            context: context
        )
        XCTAssertEqual(evaluation.status, .completed)
        XCTAssertEqual(attempt.processingStatus, .referenceAnswer)
        calls = await client.calls()
        XCTAssertEqual(calls, ["score", "feedback"])

        let answer = try await service.prepareReferenceAnswer(
            attemptID: attempt.id,
            context: context
        )
        XCTAssertFalse(answer.answerText.isEmpty)
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertFalse(attempt.referenceAnswerTextSnapshot.isEmpty)
        calls = await client.calls()
        XCTAssertEqual(calls, ["score", "feedback", "reference"])
    }

    @MainActor
    func testInvalidFeedbackKeepsScoreAndAdvancesToReferenceAnswer() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, includeReferenceAnswer: false)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "The control plane stores desired state and workers reconcile it.",
            context: context
        )
        let service = AnswerProcessingService(aiClient: FeedbackFallbackAIClient())

        let evaluation = try await service.score(attemptID: attempt.id, context: context)
        try await service.completeFeedback(
            attemptID: attempt.id,
            evaluationID: evaluation.id,
            context: context
        )

        XCTAssertEqual(evaluation.status, .completed)
        XCTAssertEqual(evaluation.provider, "local-safe-fallback")
        XCTAssertEqual(attempt.processingStatus, .referenceAnswer)
        XCTAssertNil(attempt.failureSummary)
        let detail = try JSONDecoder().decode(
            EvaluationDetailPayload.self,
            from: Data(evaluation.feedbackJSON.utf8)
        )
        XCTAssertEqual(detail.dimensions.count, 6)
        XCTAssertFalse(detail.warnings.isEmpty)
        XCTAssertTrue(detail.dimensions.allSatisfy { !$0.evidence.isEmpty })

        let answer = try await service.prepareReferenceAnswer(
            attemptID: attempt.id,
            context: context
        )
        XCTAssertFalse(answer.answerText.isEmpty)
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertFalse(attempt.referenceAnswerTextSnapshot.isEmpty)
    }

    @MainActor
    func testMalformedFeedbackResponseKeepsScoreAndAdvancesToReferenceAnswer() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, includeReferenceAnswer: false)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "The control plane stores desired state and workers reconcile it.",
            context: context
        )
        let service = AnswerProcessingService(aiClient: MalformedFeedbackAIClient())

        let evaluation = try await service.score(attemptID: attempt.id, context: context)
        try await service.completeFeedback(
            attemptID: attempt.id,
            evaluationID: evaluation.id,
            context: context
        )

        XCTAssertEqual(evaluation.status, .completed)
        XCTAssertEqual(evaluation.provider, "local-safe-fallback")
        XCTAssertEqual(attempt.processingStatus, .referenceAnswer)
        XCTAssertNil(attempt.failureSummary)
        let detail = try JSONDecoder().decode(
            EvaluationDetailPayload.self,
            from: Data(evaluation.feedbackJSON.utf8)
        )
        XCTAssertEqual(detail.dimensions.count, 6)
        XCTAssertFalse(detail.warnings.isEmpty)

        let answer = try await service.prepareReferenceAnswer(
            attemptID: attempt.id,
            context: context
        )
        XCTAssertFalse(answer.answerText.isEmpty)
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertFalse(attempt.referenceAnswerTextSnapshot.isEmpty)
    }
}

private actor RecordingAIClient: AIClient {
    private let base = StubAIClient()
    private var polishCalls = 0
    private var evaluateCalls = 0
    private var referenceAnswerCalls = 0
    private var evaluationRequest: EvaluationRequest?
    private var referenceAnswerRequest: ReferenceAnswerRequest?

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await base.decompose(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        referenceAnswerCalls += 1
        referenceAnswerRequest = request
        return try await base.referenceAnswer(request)
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
    func referenceAnswerCallCount() -> Int { referenceAnswerCalls }
    func lastReferenceAnswerRequest() -> ReferenceAnswerRequest? { referenceAnswerRequest }
}

private actor StagedRecordingAIClient: AIClient {
    private let base = StubAIClient()
    private var recordedCalls: [String] = []

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await base.decompose(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        recordedCalls.append("reference")
        return try await base.referenceAnswer(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        recordedCalls.append("score")
        let response = try await base.evaluate(request.asEvaluationRequest())
        return EvaluationScoreResponse(
            scorable: response.scorable,
            notScorableReason: response.notScorableReason,
            dimensions: response.dimensions.map { .init(key: $0.key, score: $0.score) },
            confidence: response.confidence,
            scoreRange: response.scoreRange,
            warnings: response.warnings,
            modelID: response.modelID,
            promptVersion: PromptCatalog.evaluateScoreVersion,
            rubricVersion: response.rubricVersion,
            completionStatus: response.completionStatus
        )
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        recordedCalls.append("feedback")
        let response = try await base.evaluate(request.asEvaluationRequest())
        return EvaluationFeedbackResponse(
            dimensions: response.dimensions.map {
                .init(key: $0.key, evidence: $0.evidence, missedPoints: $0.missedPoints, feedback: $0.feedback)
            },
            factualErrors: response.factualErrors,
            strengths: response.strengths,
            gapsAndErrors: response.gapsAndErrors,
            improvements: response.improvements,
            polishOnlyClaims: response.polishOnlyClaims,
            confidence: response.confidence,
            scoreRange: response.scoreRange,
            warnings: response.warnings,
            modelID: response.modelID,
            promptVersion: PromptCatalog.evaluateFeedbackVersion,
            rubricVersion: response.rubricVersion,
            completionStatus: response.completionStatus
        )
    }

    func calls() -> [String] { recordedCalls }
}

private actor FeedbackFallbackAIClient: AIClient {
    private let base = StubAIClient()

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await base.decompose(request)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try await base.referenceAnswer(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        try await base.score(request)
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        throw AIResponseValidationError.emptyField("evaluation.missedPoints.technicalCorrectness")
    }
}

private actor MalformedFeedbackAIClient: AIClient {
    private let base = StubAIClient()

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await base.decompose(request)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try await base.referenceAnswer(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        try await base.score(request)
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        throw AIError.malformedStructuredResponse
    }
}
