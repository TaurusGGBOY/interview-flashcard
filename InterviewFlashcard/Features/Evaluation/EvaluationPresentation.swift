import Foundation

struct EvaluationDimensionRow: Equatable, Sendable {
    let dimension: ScoreDimension
    let score: Int
    let feedback: String
    let evidence: [EvaluationEvidence]
    let missedPoints: [String]

    init(
        dimension: ScoreDimension,
        score: Int,
        feedback: String,
        evidence: [EvaluationEvidence] = [],
        missedPoints: [String] = []
    ) {
        self.dimension = dimension
        self.score = score
        self.feedback = feedback
        self.evidence = evidence
        self.missedPoints = missedPoints
    }
}

struct EvaluationPresentation: Equatable, Sendable {
    let totalScore: Int?
    let dimensions: [EvaluationDimensionRow]
    let strengths: [String]
    let improvements: [String]
    let factualErrors: [String]
    let gaps: [String]
    let warnings: [String]
    let scoreRange: ScoreRange?
    let confidence: Double?
    let rawText: String
    let polishedText: String?
    let referenceAnswer: String
    let referenceVersion: Int

    init(evaluation: EvaluationRecord) {
        let payload = Self.decodePayload(evaluation.feedbackJSON)
        let feedback = Self.decodeDictionary(evaluation.feedbackJSON)
        let payloadDimensions = (payload?.dimensions ?? []).reduce(into: [ScoreDimension: EvaluationDimension]()) {
            $0[$1.key] = $1
        }
        dimensions = ScoreDimension.allCases.map { dimension in
            if let detail = payloadDimensions[dimension] {
                return EvaluationDimensionRow(
                    dimension: dimension,
                    score: detail.score,
                    feedback: detail.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "暂无该维度的文字反馈。"
                        : detail.feedback,
                    evidence: detail.evidence,
                    missedPoints: detail.missedPoints
                )
            }
            return EvaluationDimensionRow(
                dimension: dimension,
                score: evaluation.dimensionScores[dimension],
                feedback: feedback[dimension.rawValue] ?? "暂无该维度的文字反馈。"
            )
        }
        totalScore = evaluation.totalScore
        if let payload, !payload.strengths.isEmpty {
            strengths = payload.strengths
        } else {
            strengths = Self.decodeStrings(evaluation.strengthsJSON)
        }
        if let payload, !payload.improvements.isEmpty {
            improvements = payload.improvements
        } else {
            improvements = Self.decodeStrings(evaluation.nextAnswerPlanJSON)
        }
        if let payload, !payload.factualErrors.isEmpty {
            factualErrors = Self.renderFactualErrors(payload.factualErrors)
        } else {
            factualErrors = Self.decodeFactualErrors(evaluation.factualErrorsJSON)
        }
        gaps = payload?.gaps ?? []
        warnings = payload?.warnings ?? []
        scoreRange = payload?.scoreRange
        confidence = payload?.confidence
        rawText = evaluation.attempt.rawText
        let latestPolishedText = evaluation.attempt.polishResults
            .max { lhs, rhs in
                if lhs.revision == rhs.revision { return lhs.createdAt < rhs.createdAt }
                return lhs.revision < rhs.revision
            }?
            .polishedText
        polishedText = latestPolishedText == rawText ? nil : latestPolishedText
        referenceAnswer = evaluation.attempt.referenceAnswerTextSnapshot
        referenceVersion = evaluation.attempt.referenceAnswerVersion
    }

    private static func decodePayload(_ json: String) -> EvaluationDetailPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EvaluationDetailPayload.self, from: data)
    }

    static func decodeStrings(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func decodeDictionary(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func decodeFactualErrors(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([FactualError].self, from: data) else {
            return []
        }
        return renderFactualErrors(values)
    }

    private static func renderFactualErrors(_ values: [FactualError]) -> [String] {
        values.map { "\($0.statement)：\($0.explanation)" }
    }
}
