import Foundation
import XCTest
@testable import InterviewFlashcard

final class AIResponseValidatorTests: XCTestCase {
    func testEvaluationRejectsMissingDimensionAndComputesNoModelTotal() throws {
        let response = makeEvaluation(
            dimensions: makeDimensions().filter { $0.key != .precision }
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个。"
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .missingDimension(.precision))
        }
    }

    func testEvaluationRejectsCorrectnessCreditThatExistsOnlyInPolishedText() throws {
        var dimensions = makeDimensions()
        let index = try XCTUnwrap(dimensions.firstIndex(where: { $0.key == .correctness }))
        dimensions[index] = EvaluationDimension(
            key: .correctness,
            score: 80,
            evidence: [.init(quote: "分区容错", explanation: "仅由润色新增")],
            missedPoints: [],
            feedback: "不应计分"
        )
        let response = makeEvaluation(dimensions: dimensions)

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 的三个要素包括一致性、可用性和分区容错。"
            )
        ) { error in
            XCTAssertEqual(
                error as? AIResponseValidationError,
                .polishOnlyEvidenceCredited(.correctness, "分区容错")
            )
        }
    }

    func testEvaluationRejectsDuplicateDimensionAndOutOfRangeScore() throws {
        var duplicate = makeDimensions()
        duplicate[5] = duplicate[0]
        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                makeEvaluation(dimensions: duplicate),
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个。"
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .duplicateDimension(.correctness))
        }

        var outOfRange = makeDimensions()
        outOfRange[0] = EvaluationDimension(
            key: .correctness,
            score: 101,
            evidence: [.init(quote: "CAP", explanation: "原文证据")],
            missedPoints: [],
            feedback: "越界"
        )
        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                makeEvaluation(dimensions: outOfRange),
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个。"
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .scoreOutOfRange(.correctness, 101))
        }
    }

    func testDecomposeRejectsDuplicateIDsMissingAnchorsAndTruncation() throws {
        let sourceID = UUID()
        let chunkID = UUID()
        let request = DecomposeRequest(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            markdown: "CAP theorem",
            ownedStartOffset: 0,
            ownedEndOffset: 11
        )
        let anchor = SourceAnchor(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            startOffset: 0,
            endOffset: 3,
            exactQuote: "CAP"
        )
        let id = UUID()
        let candidate = CandidateDraft(
            id: id,
            ordinal: 0,
            question: "什么是 CAP？",
            sourceBackedAnswerMaterial: "CAP theorem",
            sourceAnchors: [anchor]
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                .init(candidates: [candidate, candidate], completionStatus: .complete),
                for: request
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .duplicateID(id.uuidString))
        }

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                .init(candidates: [], completionStatus: .truncated),
                for: request
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .truncated)
        }
    }

    func testClientComputesFixedWeightedTotalAsSeventyFive() throws {
        let dimensions = makeDimensions()
        XCTAssertEqual(EvaluationRubric.general.total(for: dimensions), 75)
        XCTAssertEqual(
            ScoringRubric.general.total(
                for: DimensionScores(
                    correctness: 80,
                    coverage: 60,
                    reasoning: 80,
                    structure: 80,
                    tradeoffs: 70,
                    precision: 100
                )
            ),
            75
        )
    }

    private func makeDimensions() -> [EvaluationDimension] {
        let scores: [(ScoreDimension, Int)] = [
            (.correctness, 80),
            (.coverage, 60),
            (.reasoning, 80),
            (.structure, 80),
            (.tradeoffs, 70),
            (.precision, 100)
        ]
        return scores.map { key, score in
            EvaluationDimension(
                key: key,
                score: score,
                evidence: [.init(quote: "CAP", explanation: "原文证据")],
                missedPoints: [],
                feedback: "测试反馈"
            )
        }
    }

    private func makeEvaluation(dimensions: [EvaluationDimension]) -> EvaluationResponse {
        EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: dimensions,
            factualErrors: [],
            strengths: ["有核心结论"],
            gapsAndErrors: [],
            improvements: ["补充边界"],
            polishOnlyClaims: [],
            confidence: 0.9,
            scoreRange: .init(low: 70, high: 80),
            warnings: [],
            modelID: "test-model",
            promptVersion: PromptCatalog.evaluateVersion,
            rubricVersion: EvaluationRubric.general.version,
            completionStatus: .complete
        )
    }
}
