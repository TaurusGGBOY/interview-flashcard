import Foundation
import XCTest

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
            missedPoints: ["补充原始回答中的边界"],
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
            missedPoints: ["补充边界"],
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

    func testEvaluationDecodingNormalizesProviderRubricAliases() throws {
        let payload = """
        {
          "scorable": true,
          "notScorableReason": "",
          "dimensions": [
            {"key":"accuracy","score":95,"evidence":[{"quote":"raw fragment","explanation":"准确"}],"missedPoints":["补充边界"],"feedback":"准确"},
            {"key":"completeness","score":86,"evidence":[{"quote":"raw fragment","explanation":"覆盖"}],"missedPoints":["补充边界"],"feedback":"覆盖"},
            {"key":"clarity","score":78,"evidence":[{"quote":"raw fragment","explanation":"清晰"}],"missedPoints":["补充边界"],"feedback":"清晰"},
            {"key":"technicalDepth","score":90,"evidence":[{"quote":"raw fragment","explanation":"深入"}],"missedPoints":["补充边界"],"feedback":"深入"},
            {"key":"conciseness","score":95,"evidence":[{"quote":"raw fragment","explanation":"简洁"}],"missedPoints":["补充边界"],"feedback":"简洁"},
            {"key":"codeCorrectness","score":88,"evidence":[{"quote":"raw fragment","explanation":"实现"}],"missedPoints":["补充边界"],"feedback":"实现"}
          ],
          "factualErrors": [],
          "strengths": ["核心结论正确"],
          "gapsAndErrors": ["补充边界"],
          "improvements": ["补充边界"],
          "polishOnlyClaims": [],
          "confidence": 90,
          "scoreRange": {"low": 80, "high": 95},
          "warnings": [],
          "modelID": "deepseek-v4-flash",
          "promptVersion": "evaluate-senior-v3",
          "rubricVersion": "senior-software-engineer-v2",
          "completionStatus": "complete"
        }
        """

        let response = try JSONDecoder().decode(
            EvaluationResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(response.notScorableReason)
        XCTAssertEqual(response.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(
            response.dimensions.map(\.key),
            [.correctness, .coverage, .structure, .reasoning, .precision, .tradeoffs]
        )
        try AIResponseValidator.validate(
            response,
            rubric: EvaluationRubric.seniorSoftwareEngineer,
            rawText: "raw fragment",
            polishedText: "raw fragment"
        )
    }

    func testSeniorEvaluationRejectsVersionMismatchAndUnsupportedEvidence() throws {
        let response = makeEvaluation(
            rubric: .seniorSoftwareEngineer,
            promptVersion: "wrong-prompt"
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: .seniorSoftwareEngineer,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个"
            )
        )

        let unsupported = makeEvaluation(
            dimensions: makeDimensions(rubric: .seniorSoftwareEngineer).map { dimension in
                guard dimension.key == .correctness else { return dimension }
                return EvaluationDimension(
                    key: dimension.key,
                    score: dimension.score,
                    evidence: [.init(quote: "模型编造的句子", explanation: "看似像证据")],
                    missedPoints: dimension.missedPoints,
                    feedback: dimension.feedback
                )
            }
        )
        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                unsupported,
                rubric: .seniorSoftwareEngineer,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个"
            )
        )
    }

    func testSeniorEvaluationRequiresSpecificFeedbackEvidenceAndMissedPoints() throws {
        var dimensions = makeDimensions(rubric: .seniorSoftwareEngineer)
        dimensions[0] = EvaluationDimension(
            key: .correctness,
            score: 80,
            evidence: [.init(quote: "CAP", explanation: "")],
            missedPoints: [],
            feedback: ""
        )
        let response = makeEvaluation(
            dimensions: dimensions,
            rubric: .seniorSoftwareEngineer,
            gapsAndErrors: [],
            improvements: []
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: .seniorSoftwareEngineer,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个"
            )
        )
    }

    private func makeDimensions(rubric: EvaluationRubric = .general) -> [EvaluationDimension] {
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
                missedPoints: score == 100 ? [] : ["补充一个边界条件"],
                feedback: "测试反馈"
            )
        }
    }

    private func makeEvaluation(
        dimensions: [EvaluationDimension]? = nil,
        rubric: EvaluationRubric = .general,
        promptVersion: String? = nil,
        gapsAndErrors: [String] = ["缺少边界"],
        improvements: [String] = ["补充边界"]
    ) -> EvaluationResponse {
        EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: dimensions ?? makeDimensions(rubric: rubric),
            factualErrors: [],
            strengths: ["有核心结论"],
            gapsAndErrors: gapsAndErrors,
            improvements: improvements,
            polishOnlyClaims: [],
            confidence: 0.9,
            scoreRange: .init(low: 70, high: 80),
            warnings: [],
            modelID: "test-model",
            promptVersion: promptVersion ?? PromptCatalog.evaluateVersion,
            rubricVersion: rubric.version,
            completionStatus: .complete
        )
    }
}
