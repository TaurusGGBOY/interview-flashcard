import Foundation

/// The versioned, auditable detail stored in `EvaluationRecord.feedbackJSON`.
///
/// `EvaluationRecord` predates dimension evidence, so the record schema remains
/// unchanged and this payload carries the richer v2 contract instead.
struct EvaluationDetailPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let scorable: Bool
    let notScorableReason: String?
    let dimensions: [EvaluationDimension]
    let strengths: [String]
    let gaps: [String]
    let improvements: [String]
    let factualErrors: [FactualError]
    let polishOnlyClaims: [String]
    let warnings: [String]
    let confidence: Double
    let scoreRange: ScoreRange
    let modelID: String
    let promptVersion: String
    let rubricVersion: String

    var gapsAndErrors: [String] { gaps }

    init(evaluation: EvaluationResponse, schemaVersion: Int = currentSchemaVersion) {
        self.init(
            schemaVersion: schemaVersion,
            scorable: evaluation.scorable,
            notScorableReason: evaluation.notScorableReason,
            dimensions: evaluation.dimensions,
            strengths: evaluation.strengths,
            gaps: evaluation.gapsAndErrors,
            improvements: evaluation.improvements,
            factualErrors: evaluation.factualErrors,
            polishOnlyClaims: evaluation.polishOnlyClaims,
            warnings: evaluation.warnings,
            confidence: evaluation.confidence,
            scoreRange: evaluation.scoreRange,
            modelID: evaluation.modelID,
            promptVersion: evaluation.promptVersion,
            rubricVersion: evaluation.rubricVersion
        )
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        scorable: Bool,
        notScorableReason: String? = nil,
        dimensions: [EvaluationDimension],
        strengths: [String] = [],
        gaps: [String] = [],
        improvements: [String] = [],
        factualErrors: [FactualError] = [],
        polishOnlyClaims: [String] = [],
        warnings: [String] = [],
        confidence: Double = 0,
        scoreRange: ScoreRange = .init(low: 0, high: 0),
        modelID: String = "",
        promptVersion: String = "",
        rubricVersion: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.scorable = scorable
        self.notScorableReason = notScorableReason
        self.dimensions = dimensions
        self.strengths = strengths
        self.gaps = gaps
        self.improvements = improvements
        self.factualErrors = factualErrors
        self.polishOnlyClaims = polishOnlyClaims
        self.warnings = warnings
        self.confidence = confidence
        self.scoreRange = scoreRange
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.rubricVersion = rubricVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case scorable
        case notScorableReason
        case dimensions
        case strengths
        case gaps
        case gapsAndErrors
        case improvements
        case factualErrors
        case polishOnlyClaims
        case warnings
        case confidence
        case scoreRange
        case modelID
        case promptVersion
        case rubricVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        scorable = try container.decode(Bool.self, forKey: .scorable)
        notScorableReason = try container.decodeIfPresent(String.self, forKey: .notScorableReason)
        dimensions = try container.decode([EvaluationDimension].self, forKey: .dimensions)
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths) ?? []
        gaps = try container.decodeIfPresent([String].self, forKey: .gaps)
            ?? (try container.decodeIfPresent([String].self, forKey: .gapsAndErrors))
            ?? []
        improvements = try container.decodeIfPresent([String].self, forKey: .improvements) ?? []
        factualErrors = try container.decodeIfPresent([FactualError].self, forKey: .factualErrors) ?? []
        polishOnlyClaims = try container.decodeIfPresent([String].self, forKey: .polishOnlyClaims) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        scoreRange = try container.decodeIfPresent(ScoreRange.self, forKey: .scoreRange)
            ?? .init(low: 0, high: 0)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? ""
        promptVersion = try container.decodeIfPresent(String.self, forKey: .promptVersion) ?? ""
        rubricVersion = try container.decodeIfPresent(String.self, forKey: .rubricVersion) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(scorable, forKey: .scorable)
        try container.encodeIfPresent(notScorableReason, forKey: .notScorableReason)
        try container.encode(dimensions, forKey: .dimensions)
        try container.encode(strengths, forKey: .strengths)
        try container.encode(gaps, forKey: .gaps)
        try container.encode(improvements, forKey: .improvements)
        try container.encode(factualErrors, forKey: .factualErrors)
        try container.encode(polishOnlyClaims, forKey: .polishOnlyClaims)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(scoreRange, forKey: .scoreRange)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(promptVersion, forKey: .promptVersion)
        try container.encode(rubricVersion, forKey: .rubricVersion)
    }
}
