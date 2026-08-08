import Foundation
import XCTest

final class EvaluationDetailPayloadTests: XCTestCase {
    func testSeniorRubricHasStableVersionOrderAndWeights() {
        let rubric = EvaluationRubric.seniorSoftwareEngineer

        XCTAssertEqual(rubric.version, "senior-software-engineer-v2")
        XCTAssertEqual(rubric.dimensions.map(\.key), ScoreDimension.allCases)
        XCTAssertEqual(rubric.dimensions.map(\.weight), [35, 25, 15, 10, 10, 5])
        XCTAssertEqual(PromptCatalog.evaluateVersion, "evaluate-senior-v3")
    }

    func testV2PayloadRoundTripsAllEvidenceAndSummaryFields() throws {
        let dimensions = ScoreDimension.allCases.map { dimension in
            EvaluationDimension(
                key: dimension,
                score: dimension == .precision ? 100 : 80,
                evidence: [
                    EvaluationEvidence(
                        quote: "原始回答片段",
                        explanation: "这句话直接支持该维度的判断。"
                    )
                ],
                missedPoints: dimension == .precision ? [] : ["还缺少一个边界条件"],
                feedback: "针对本题的具体反馈。"
            )
        }
        let source = EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: dimensions,
            factualErrors: [],
            strengths: ["核心结论"],
            gapsAndErrors: ["缺少失败场景"],
            improvements: ["补充超时和重试边界"],
            polishOnlyClaims: [],
            confidence: 0.82,
            scoreRange: .init(low: 70, high: 85),
            warnings: ["回答来自语音转写"],
            modelID: "deepseek",
            promptVersion: PromptCatalog.evaluateVersion,
            rubricVersion: EvaluationRubric.seniorSoftwareEngineer.version,
            completionStatus: .complete
        )

        let payload = EvaluationDetailPayload(evaluation: source)
        XCTAssertEqual(payload.schemaVersion, 2)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(EvaluationDetailPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.dimensions.count, 6)
        XCTAssertEqual(decoded.gaps, ["缺少失败场景"])
        XCTAssertEqual(decoded.warnings, ["回答来自语音转写"])
        XCTAssertEqual(decoded.scoreRange, .init(low: 70, high: 85))
    }
}
