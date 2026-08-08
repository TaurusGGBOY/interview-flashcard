import Foundation

enum AICompletionStatus: String, Codable, Equatable, Sendable {
    case complete
    case truncated
}

struct SourceAnchor: Codable, Equatable, Hashable, Sendable {
    let sourceDocumentID: UUID
    let chunkID: UUID
    let startOffset: Int
    let endOffset: Int
    let exactQuote: String

    init(
        sourceDocumentID: UUID,
        chunkID: UUID,
        startOffset: Int,
        endOffset: Int,
        exactQuote: String
    ) {
        self.sourceDocumentID = sourceDocumentID
        self.chunkID = chunkID
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.exactQuote = exactQuote
    }
}

struct DecomposeRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let sourceDocumentID: UUID
    let chunkID: UUID
    let contextBefore: String
    let ownedMarkdown: String
    let contextAfter: String
    let ownedStartOffset: Int
    let ownedEndOffset: Int
    let localeIdentifier: String

    var markdown: String {
        contextBefore + ownedMarkdown + contextAfter
    }

    init(
        requestID: UUID = UUID(),
        sourceDocumentID: UUID,
        chunkID: UUID,
        markdown: String,
        contextBefore: String = "",
        contextAfter: String = "",
        ownedStartOffset: Int,
        ownedEndOffset: Int,
        localeIdentifier: String = "zh-CN"
    ) {
        self.requestID = requestID
        self.sourceDocumentID = sourceDocumentID
        self.chunkID = chunkID
        self.contextBefore = contextBefore
        self.ownedMarkdown = markdown
        self.contextAfter = contextAfter
        self.ownedStartOffset = ownedStartOffset
        self.ownedEndOffset = ownedEndOffset
        self.localeIdentifier = localeIdentifier
    }
}

struct CandidateDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let ordinal: Int
    let question: String
    let sourceBackedAnswerMaterial: String
    let sourceAnchors: [SourceAnchor]
}

struct DecomposeResponse: Codable, Equatable, Sendable {
    let candidates: [CandidateDraft]
    let completionStatus: AICompletionStatus
}

struct RefineRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let sourceDocumentID: UUID
    let batchID: UUID
    let candidates: [CandidateDraft]
    let availableTopicNames: [String]

    init(
        requestID: UUID = UUID(),
        sourceDocumentID: UUID,
        batchID: UUID,
        candidates: [CandidateDraft],
        availableTopicNames: [String]
    ) {
        self.requestID = requestID
        self.sourceDocumentID = sourceDocumentID
        self.batchID = batchID
        self.candidates = candidates
        self.availableTopicNames = availableTopicNames
    }
}

struct RefinedCardDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let mergedCandidateIDs: [UUID]
    let question: String
    let fullScoreAnswer: String
    let topicName: String
    let sourceAnchors: [SourceAnchor]
}

struct RefineResponse: Codable, Equatable, Sendable {
    let cards: [RefinedCardDraft]
    let completionStatus: AICompletionStatus
}

struct ReclassificationCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let question: String
    let fullScoreAnswer: String
}

struct ReclassifyRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let batchID: UUID
    let cards: [ReclassificationCard]
    let availableTopicNames: [String]

    init(
        requestID: UUID = UUID(),
        batchID: UUID,
        cards: [ReclassificationCard],
        availableTopicNames: [String]
    ) {
        self.requestID = requestID
        self.batchID = batchID
        self.cards = cards
        self.availableTopicNames = availableTopicNames
    }
}

struct ReclassificationAssignment: Codable, Equatable, Sendable {
    let cardID: UUID
    let topicName: String
}

struct ReclassifyResponse: Codable, Equatable, Sendable {
    let assignments: [ReclassificationAssignment]
    let completionStatus: AICompletionStatus
}

struct PolishRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let rawText: String
    let localeIdentifier: String
    let terminologyHints: [String]

    init(
        requestID: UUID = UUID(),
        rawText: String,
        localeIdentifier: String,
        terminologyHints: [String] = []
    ) {
        self.requestID = requestID
        self.rawText = rawText
        self.localeIdentifier = localeIdentifier
        self.terminologyHints = terminologyHints
    }
}

struct PolishEdit: Codable, Equatable, Sendable {
    let original: String
    let replacement: String
    let reason: String
}

struct SuspectedTranscriptionIssue: Codable, Equatable, Sendable {
    let text: String
    let alternatives: [String]
    let reason: String
}

struct IntroducedClaim: Codable, Equatable, Sendable {
    let text: String
    let reason: String
}

struct PolishResponse: Codable, Equatable, Sendable {
    let polishedText: String
    let edits: [PolishEdit]
    let suspectedTranscriptionIssues: [SuspectedTranscriptionIssue]
    let introducedClaims: [IntroducedClaim]
    let needsUserReview: Bool
    let warnings: [String]
    let modelID: String
    let promptVersion: String
    let completionStatus: AICompletionStatus
}

struct EvaluationRubricDimension: Codable, Equatable, Sendable {
    let key: ScoreDimension
    let weight: Int
    let fullScoreMeaning: String
}

struct EvaluationRubric: Codable, Equatable, Sendable {
    let version: String
    let dimensions: [EvaluationRubricDimension]

    static let general = EvaluationRubric(
        version: "general-v1",
        dimensions: [
            .init(key: .correctness, weight: 35, fullScoreMeaning: "结论和核心机制正确"),
            .init(key: .coverage, weight: 25, fullScoreMeaning: "覆盖题目关键点"),
            .init(key: .reasoning, weight: 15, fullScoreMeaning: "解释因果、边界和原理"),
            .init(key: .structure, weight: 10, fullScoreMeaning: "结构清楚，适合口述"),
            .init(key: .tradeoffs, weight: 10, fullScoreMeaning: "包含恰当示例或取舍"),
            .init(key: .precision, weight: 5, fullScoreMeaning: "术语准确且简洁")
        ]
    )

    /// Stable rubric used for all new practice evaluations. Keep the order in
    /// lockstep with `ScoreDimension.allCases`; the order is part of the
    /// persisted presentation contract.
    static let seniorSoftwareEngineer = EvaluationRubric(
        version: "senior-software-engineer-v2",
        dimensions: [
            .init(key: .correctness, weight: 35, fullScoreMeaning: "结论、事实和核心机制正确"),
            .init(key: .coverage, weight: 25, fullScoreMeaning: "覆盖参考答案中的关键点和边界"),
            .init(key: .reasoning, weight: 15, fullScoreMeaning: "解释因果、机制、边界和失败模式"),
            .init(key: .structure, weight: 10, fullScoreMeaning: "回答结构清晰，便于面试口述和追问"),
            .init(key: .tradeoffs, weight: 10, fullScoreMeaning: "给出应用场景、取舍和工程约束"),
            .init(key: .precision, weight: 5, fullScoreMeaning: "术语准确、范围明确且表达简洁")
        ]
    )

    func total(for dimensions: [EvaluationDimension]) -> Int? {
        var scores: [ScoreDimension: Int] = [:]
        for dimension in dimensions {
            guard scores.updateValue(dimension.score, forKey: dimension.key) == nil else {
                return nil
            }
        }
        guard scores.count == self.dimensions.count,
              Set(scores.keys) == Set(self.dimensions.map(\.key)) else {
            return nil
        }
        let weighted = self.dimensions.reduce(0.0) { result, dimension in
            result + Double(scores[dimension.key] ?? 0) * Double(dimension.weight) / 100.0
        }
        return Int(weighted.rounded())
    }
}

struct EvaluationRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let question: String
    let referenceAnswer: String
    let rawText: String
    let polishedText: String
    let introducedClaims: [IntroducedClaim]
    let rubric: EvaluationRubric

    init(
        requestID: UUID = UUID(),
        question: String,
        referenceAnswer: String,
        rawText: String,
        polishedText: String,
        introducedClaims: [IntroducedClaim],
        rubric: EvaluationRubric = .seniorSoftwareEngineer
    ) {
        self.requestID = requestID
        self.question = question
        self.referenceAnswer = referenceAnswer
        self.rawText = rawText
        self.polishedText = polishedText
        self.introducedClaims = introducedClaims
        self.rubric = rubric
    }
}

struct EvaluationEvidence: Codable, Equatable, Sendable {
    let quote: String
    let explanation: String
}

struct EvaluationDimension: Codable, Equatable, Sendable {
    let key: ScoreDimension
    let score: Int
    let evidence: [EvaluationEvidence]
    let missedPoints: [String]
    let feedback: String
}

struct FactualError: Codable, Equatable, Sendable {
    let statement: String
    let explanation: String
    let referenceBasis: String
}

struct ScoreRange: Codable, Equatable, Sendable {
    let low: Int
    let high: Int
}

struct EvaluationResponse: Codable, Equatable, Sendable {
    let scorable: Bool
    let notScorableReason: String?
    let dimensions: [EvaluationDimension]
    let factualErrors: [FactualError]
    let strengths: [String]
    let gapsAndErrors: [String]
    let improvements: [String]
    let polishOnlyClaims: [String]
    let confidence: Double
    let scoreRange: ScoreRange
    let warnings: [String]
    let modelID: String
    let promptVersion: String
    let rubricVersion: String
    let completionStatus: AICompletionStatus

    init(
        scorable: Bool,
        notScorableReason: String?,
        dimensions: [EvaluationDimension],
        factualErrors: [FactualError],
        strengths: [String],
        gapsAndErrors: [String],
        improvements: [String],
        polishOnlyClaims: [String],
        confidence: Double,
        scoreRange: ScoreRange,
        warnings: [String],
        modelID: String,
        promptVersion: String,
        rubricVersion: String,
        completionStatus: AICompletionStatus
    ) {
        self.scorable = scorable
        self.notScorableReason = notScorableReason
        self.dimensions = dimensions
        self.factualErrors = factualErrors
        self.strengths = strengths
        self.gapsAndErrors = gapsAndErrors
        self.improvements = improvements
        self.polishOnlyClaims = polishOnlyClaims
        self.confidence = confidence
        self.scoreRange = scoreRange
        self.warnings = warnings
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.rubricVersion = rubricVersion
        self.completionStatus = completionStatus
    }

    private enum CodingKeys: String, CodingKey {
        case scorable
        case notScorableReason
        case dimensions
        case factualErrors
        case strengths
        case gapsAndErrors
        case improvements
        case polishOnlyClaims
        case confidence
        case scoreRange
        case warnings
        case modelID
        case promptVersion
        case rubricVersion
        case completionStatus
    }

    /// DeepSeek occasionally emits a compact rubric shape such as
    /// `{ "technicalCorrectness": 4, "evidence": ["..."] }` instead of
    /// the documented `{ "key": "technicalCorrectness", "score": 80 }`.
    /// Accept that response at the AI boundary so a valid model result is not
    /// discarded; the canonical shape is still what the app persists.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scorable = try container.decode(Bool.self, forKey: .scorable)
        let decodedNotScorableReason = try container.decodeIfPresent(String.self, forKey: .notScorableReason)
        notScorableReason = decodedNotScorableReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : decodedNotScorableReason
        dimensions = try container.decode([FlexibleEvaluationDimension].self, forKey: .dimensions).map(\.value)
        factualErrors = try container.decode([FactualError].self, forKey: .factualErrors)
        strengths = try container.decode([String].self, forKey: .strengths)
        gapsAndErrors = try container.decode([String].self, forKey: .gapsAndErrors)
        improvements = try container.decode([String].self, forKey: .improvements)
        polishOnlyClaims = try container.decode([String].self, forKey: .polishOnlyClaims)
        let decodedConfidence = try container.decode(Double.self, forKey: .confidence)
        // Some providers return confidence as a percentage (for example 90)
        // even when the contract asks for a 0...1 value. Normalize that
        // harmless representation at the AI boundary before validation.
        confidence = decodedConfidence > 1 && decodedConfidence <= 100
            ? decodedConfidence / 100
            : decodedConfidence
        scoreRange = try container.decode(ScoreRange.self, forKey: .scoreRange)
        warnings = try container.decode([String].self, forKey: .warnings)
        modelID = try container.decode(String.self, forKey: .modelID)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        rubricVersion = try container.decode(String.self, forKey: .rubricVersion)
        completionStatus = try container.decode(AICompletionStatus.self, forKey: .completionStatus)
    }
}

private struct FlexibleEvaluationDimension: Decodable {
    let value: EvaluationDimension

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let keyField = AnyCodingKey("key")
        let scoreField = AnyCodingKey("score")

        if let rawKey = try? container.decode(String.self, forKey: keyField),
           let key = Self.canonicalDimension(rawKey),
           let score = try? container.decode(Int.self, forKey: scoreField) {
            let evidence = try container.decode([EvaluationEvidence].self, forKey: AnyCodingKey("evidence"))
            let missedPoints = try container.decode([String].self, forKey: AnyCodingKey("missedPoints"))
            let feedback = try container.decode(String.self, forKey: AnyCodingKey("feedback"))
            value = EvaluationDimension(
                key: key,
                score: score,
                evidence: evidence,
                missedPoints: missedPoints,
                feedback: feedback
            )
            return
        }

        guard let dimensionField = container.allKeys.first(where: {
            Self.canonicalDimension($0.stringValue) != nil
        }),
        let key = Self.canonicalDimension(dimensionField.stringValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: keyField,
                in: container,
                debugDescription: "Evaluation dimension has no recognized key"
            )
        }

        let rawScore = try container.decode(Int.self, forKey: dimensionField)
        // Some responses use the common 1–5 rubric despite the prompt's
        // 0–100 contract. Preserve that judgment on the canonical scale.
        let normalizedScore = rawScore <= 5 ? rawScore * 20 : rawScore
        let evidenceTexts = (try? container.decode([String].self, forKey: AnyCodingKey("evidence"))) ?? []
        let evidence = evidenceTexts.map { EvaluationEvidence(quote: $0, explanation: "") }
        let missedPoints = (try? container.decode([String].self, forKey: AnyCodingKey("missedPoints"))) ?? []
        let feedback = (try? container.decode(String.self, forKey: AnyCodingKey("feedback"))) ?? ""
        value = EvaluationDimension(
            key: key,
            score: normalizedScore,
            evidence: evidence,
            missedPoints: missedPoints,
            feedback: feedback
        )
    }

    private static func canonicalDimension(_ rawValue: String) -> ScoreDimension? {
        if let canonical = ScoreDimension(rawValue: rawValue) {
            return canonical
        }

        // DeepSeek sometimes substitutes a familiar six-part rubric for the
        // app's canonical names. Keep the result usable while retaining the
        // six-dimension invariant required by persistence and presentation.
        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "") {
        case "accuracy", "technicalaccuracy", "correctness":
            return .correctness
        case "completeness", "coverage", "keypointcoverage":
            return .coverage
        case "technicaldepth", "reasoning", "reasoningdepth", "depth":
            return .reasoning
        case "clarity", "structure", "structureclarity":
            return .structure
        case "tradeoffs", "application", "applicationtradeoffs", "codecorrectness", "implementation":
            return .tradeoffs
        case "conciseness", "precision", "precisionconciseness", "brevity":
            return .precision
        default:
            return nil
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
