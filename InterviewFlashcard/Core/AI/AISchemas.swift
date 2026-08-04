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
        rubric: EvaluationRubric = .general
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
}
