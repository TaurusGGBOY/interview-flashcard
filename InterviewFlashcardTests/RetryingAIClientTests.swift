import Foundation
import XCTest

final class RetryingAIClientTests: XCTestCase {
    func testRetriesOneTransientFailureOnly() async throws {
        let base = ScriptedAIClient(decomposeErrors: [.rateLimited])
        let sut = RetryingAIClient(
            base: base,
            maximumRetries: 1,
            retryDelayNanoseconds: 0
        )

        _ = try await sut.decompose(makeRequest())

        let callCount = await base.decomposeCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testDoesNotRetryPermanentFailure() async {
        let base = ScriptedAIClient(decomposeErrors: [.invalidResponse("bad schema")])
        let sut = RetryingAIClient(
            base: base,
            maximumRetries: 1,
            retryDelayNanoseconds: 0
        )

        do {
            _ = try await sut.decompose(makeRequest())
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? AIError, .invalidResponse("bad schema"))
        }
        let callCount = await base.decomposeCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testRetriesMalformedStructuredResponseOnce() async throws {
        let base = ScriptedAIClient(decomposeErrors: [.malformedStructuredResponse])
        let sut = RetryingAIClient(
            base: base,
            maximumRetries: 1,
            retryDelayNanoseconds: 0
        )

        _ = try await sut.decompose(makeRequest())

        let callCount = await base.decomposeCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testStopsAfterConfiguredSingleRetry() async {
        let base = ScriptedAIClient(decomposeErrors: [.rateLimited, .transientHTTPStatus(503)])
        let sut = RetryingAIClient(
            base: base,
            maximumRetries: 1,
            retryDelayNanoseconds: 0
        )

        do {
            _ = try await sut.decompose(makeRequest())
            XCTFail("Expected second transient error")
        } catch {
            XCTAssertEqual(error as? AIError, .transientHTTPStatus(503))
        }
        let callCount = await base.decomposeCallCount
        XCTAssertEqual(callCount, 2)
    }

    func testRetriesProviderValidationFailureOnce() async throws {
        let base = FeedbackValidationAIClient()
        let sut = RetryingAIClient(
            base: base,
            maximumRetries: 1,
            retryDelayNanoseconds: 0
        )

        let response = try await sut.evaluationFeedback(makeFeedbackRequest())

        XCTAssertEqual(response.dimensions.count, ScoreDimension.allCases.count)
        let callCount = await base.feedbackCallCount()
        XCTAssertEqual(callCount, 2)
    }

    private func makeRequest() -> DecomposeRequest {
        DecomposeRequest(
            sourceDocumentID: UUID(),
            chunkID: UUID(),
            markdown: "CAP theorem",
            ownedStartOffset: 0,
            ownedEndOffset: 11
        )
    }

    private func makeFeedbackRequest() -> EvaluationFeedbackRequest {
        EvaluationFeedbackRequest(
            requestID: UUID(),
            question: "Q",
            referenceAnswer: "",
            sourceBackedMaterial: "",
            rawText: "answer",
            scores: ScoreDimension.allCases.map {
                EvaluationScoreDimension(key: $0, score: 70)
            }
        )
    }
}

private actor ScriptedAIClient: AIClient {
    private var decomposeErrors: [AIError]
    private(set) var decomposeCallCount = 0

    init(decomposeErrors: [AIError]) {
        self.decomposeErrors = decomposeErrors
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        decomposeCallCount += 1
        if !decomposeErrors.isEmpty {
            throw decomposeErrors.removeFirst()
        }
        return DecomposeResponse(candidates: [], completionStatus: .complete)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        RefineResponse(cards: [], completionStatus: .complete)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        ReclassifyResponse(assignments: [], completionStatus: .complete)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        throw AIError.invalidResponse("Unused test method")
    }
}

private actor FeedbackValidationAIClient: AIClient {
    private var calls = 0

    func feedbackCallCount() -> Int { calls }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        calls += 1
        if calls == 1 {
            throw AIResponseValidationError.emptyField("evaluation.evidence.applicationTradeoffs")
        }

        return EvaluationFeedbackResponse(
            dimensions: ScoreDimension.allCases.map { dimension in
                EvaluationFeedbackDimension(
                    key: dimension,
                    evidence: [EvaluationEvidence(quote: "answer", explanation: "回答中的原文。")],
                    missedPoints: ["补充一个边界条件"],
                    feedback: "回答覆盖了这个维度。"
                )
            },
            factualErrors: [],
            strengths: [],
            gapsAndErrors: [],
            improvements: ["补充一个边界条件"],
            polishOnlyClaims: [],
            confidence: 0.8,
            scoreRange: ScoreRange(low: 60, high: 80),
            warnings: [],
            modelID: "test",
            promptVersion: PromptCatalog.evaluateFeedbackVersion,
            rubricVersion: EvaluationRubric.seniorSoftwareEngineer.version,
            completionStatus: .complete
        )
    }
}
