import SwiftData
import XCTest

final class EvaluationPresentationTests: XCTestCase {
    func testRadarAccessibilityIdentifierIsStable() {
        XCTAssertEqual(PracticeAccessibilityID.radar, "evaluation.radar")
    }

    @MainActor
    func testPresentationDecodesAllFeedbackAndUsesLatestPolishRevision() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "原始回答",
            context: context
        )
        context.insert(
            PolishResultRecord(
                revision: 1,
                inputText: attempt.rawText,
                polishedText: "旧润色",
                promptVersion: "test",
                modelID: "stub",
                createdAt: Fixtures.now.addingTimeInterval(-10),
                attempt: attempt
            )
        )
        context.insert(
            PolishResultRecord(
                revision: 2,
                inputText: attempt.rawText,
                polishedText: "最新润色",
                promptVersion: "test",
                modelID: "stub",
                createdAt: Fixtures.now,
                attempt: attempt
            )
        )
        let evaluation = EvaluationRecord(
            totalScore: 82,
            scores: DimensionScores(correctness: 90, coverage: 80, reasoning: 70, structure: 85, tradeoffs: 75, precision: 88),
            strengthsJSON: "[\"结构清晰\",\"有取舍\"]",
            nextAnswerPlanJSON: "[\"补充边界条件\"]",
            factualErrorsJSON: "[{\"statement\":\"错误点\",\"explanation\":\"需要修正\",\"referenceBasis\":\"满分答案\"}]",
            feedbackJSON: "{\"technicalCorrectness\":\"事实基本准确\",\"keyPointCoverage\":\"覆盖主要点\"}",
            confidence: "0.90",
            provider: "stub",
            modelID: "stub",
            promptVersion: "test",
            rubricVersion: "test",
            attempt: attempt
        )
        context.insert(evaluation)

        let presentation = EvaluationPresentation(evaluation: evaluation)
        XCTAssertEqual(presentation.totalScore, 82)
        XCTAssertEqual(presentation.dimensions.map { $0.dimension }, ScoreDimension.allCases)
        XCTAssertEqual(presentation.dimensions.first?.feedback, "事实基本准确")
        XCTAssertEqual(presentation.dimensions[2].feedback, "暂无该维度的文字反馈。")
        XCTAssertEqual(presentation.strengths, ["结构清晰", "有取舍"])
        XCTAssertEqual(presentation.improvements, ["补充边界条件"])
        XCTAssertEqual(presentation.factualErrors, ["错误点：需要修正"])
        XCTAssertEqual(presentation.polishedText, "最新润色")
        XCTAssertEqual(presentation.referenceVersion, 1)
        XCTAssertTrue(presentation.gaps.isEmpty)
    }

    @MainActor
    func testPresentationDecodesV2EvidenceMissedPointsGapsWarningsAndScoreRange() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "原始回答片段",
            context: context
        )
        let response = EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: ScoreDimension.allCases.map { dimension in
                EvaluationDimension(
                    key: dimension,
                    score: 80,
                    evidence: [.init(quote: "原始回答片段", explanation: "具体证据")],
                    missedPoints: ["缺少一个关键边界"],
                    feedback: "针对本题的反馈"
                )
            },
            factualErrors: [],
            strengths: ["核心结论"],
            gapsAndErrors: ["缺少失败场景"],
            improvements: ["补充超时处理"],
            polishOnlyClaims: [],
            confidence: 0.8,
            scoreRange: .init(low: 70, high: 85),
            warnings: ["语音转写噪声"],
            modelID: "stub",
            promptVersion: PromptCatalog.evaluateVersion,
            rubricVersion: EvaluationRubric.seniorSoftwareEngineer.version,
            completionStatus: .complete
        )
        let evaluation = EvaluationRecord(
            totalScore: 80,
            scores: DimensionScores(correctness: 80, coverage: 80, reasoning: 80, structure: 80, tradeoffs: 80, precision: 80),
            strengthsJSON: "[]",
            nextAnswerPlanJSON: "[]",
            factualErrorsJSON: "[]",
            feedbackJSON: String(decoding: try JSONEncoder().encode(EvaluationDetailPayload(evaluation: response)), as: UTF8.self),
            confidence: "0.80",
            provider: "stub",
            modelID: "stub",
            promptVersion: PromptCatalog.evaluateVersion,
            rubricVersion: EvaluationRubric.seniorSoftwareEngineer.version,
            attempt: attempt
        )
        context.insert(evaluation)

        let presentation = EvaluationPresentation(evaluation: evaluation)
        XCTAssertEqual(presentation.dimensions.first?.evidence.first?.quote, "原始回答片段")
        XCTAssertEqual(presentation.dimensions.first?.missedPoints, ["缺少一个关键边界"])
        XCTAssertEqual(presentation.gaps, ["缺少失败场景"])
        XCTAssertEqual(presentation.warnings, ["语音转写噪声"])
        XCTAssertEqual(presentation.weaknesses, ["缺少失败场景", "补充超时处理"])
        XCTAssertEqual(presentation.scoreRange, .init(low: 70, high: 85))
    }

    @MainActor
    func testMalformedOptionalJSONFallsBackWithoutHidingScores() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "原始回答",
            context: context
        )
        let evaluation = EvaluationRecord(
            totalScore: nil,
            scores: DimensionScores(correctness: 0, coverage: 0, reasoning: 0, structure: 0, tradeoffs: 0, precision: 0),
            strengthsJSON: "not-json",
            nextAnswerPlanJSON: "{\"not\":\"an array\"}",
            factualErrorsJSON: "[]",
            feedbackJSON: "not-json",
            confidence: "0.00",
            provider: "stub",
            modelID: "stub",
            promptVersion: "test",
            rubricVersion: "test",
            attempt: attempt
        )
        context.insert(evaluation)

        let presentation = EvaluationPresentation(evaluation: evaluation)
        XCTAssertNil(presentation.totalScore)
        XCTAssertTrue(presentation.strengths.isEmpty)
        XCTAssertTrue(presentation.improvements.isEmpty)
        XCTAssertTrue(presentation.factualErrors.isEmpty)
        XCTAssertEqual(presentation.dimensions.count, ScoreDimension.allCases.count)
        XCTAssertEqual(presentation.dimensions.allSatisfy { $0.feedback.isEmpty == false }, true)
    }

    @MainActor
    func testPresentationOmitsLegacyPolishedTextWhenItMatchesRawAnswer() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "原始回答",
            context: context
        )
        context.insert(
            PolishResultRecord(
                revision: 1,
                inputText: attempt.rawText,
                polishedText: attempt.rawText,
                promptVersion: "test",
                modelID: "stub",
                createdAt: Fixtures.now,
                attempt: attempt
            )
        )
        let evaluation = EvaluationRecord(
            totalScore: 0,
            scores: DimensionScores(correctness: 0, coverage: 0, reasoning: 0, structure: 0, tradeoffs: 0, precision: 0),
            confidence: "0.00",
            provider: "stub",
            modelID: "stub",
            promptVersion: "test",
            rubricVersion: "test",
            attempt: attempt
        )
        context.insert(evaluation)

        XCTAssertNil(EvaluationPresentation(evaluation: evaluation).polishedText)
    }
}
