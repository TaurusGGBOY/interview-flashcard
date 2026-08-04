import Foundation
import XCTest
@testable import InterviewFlashcard

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

    private func makeRequest() -> DecomposeRequest {
        DecomposeRequest(
            sourceDocumentID: UUID(),
            chunkID: UUID(),
            markdown: "CAP theorem",
            ownedStartOffset: 0,
            ownedEndOffset: 11
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
