import Foundation

enum AICompletionStatus: String, Codable, Equatable, Sendable {
    case complete
    case truncated

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "complete", "completed", "done", "success":
            self = .complete
        case "truncated", "partial", "incomplete":
            self = .truncated
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown completion status"
            )
        }
    }
}

enum DecomposeOutputMode: String, Codable, Equatable, Sendable {
    case extraction
    case finalAnswer
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let quote = DecomposeResponseDecoder.string(
            in: container,
            keys: ["exactQuote", "quote", "exactSource", "sourceQuote", "text"]
        ) ?? ""
        let start = DecomposeResponseDecoder.int(
            in: container,
            keys: ["startOffset", "start", "sourceStart", "startIndex"]
        ) ?? 0

        // The coordinator rebuilds these values from exactQuote. Keep the
        // decoder permissive for providers that emit byte/character offsets
        // or non-UUID metadata, while preserving a useful shape for callers
        // that inspect the raw response.
        sourceDocumentID = DecomposeResponseDecoder.uuid(
            in: container,
            keys: ["sourceDocumentID", "sourceDocumentId", "documentID", "documentId"]
        ) ?? UUID()
        chunkID = DecomposeResponseDecoder.uuid(
            in: container,
            keys: ["chunkID", "chunkId"]
        ) ?? UUID()
        startOffset = start
        endOffset = DecomposeResponseDecoder.int(
            in: container,
            keys: ["endOffset", "end", "sourceEnd", "endIndex"]
        ) ?? start + quote.utf16.count
        exactQuote = quote
    }
}

struct DecomposeRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let sourceDocumentID: UUID
    let chunkID: UUID
    let outputMode: DecomposeOutputMode
    let contextBefore: String
    let ownedMarkdown: String
    let contextAfter: String
    let ownedStartOffset: Int
    let ownedEndOffset: Int
    let localeIdentifier: String
    let availableTopicNames: [String]

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
        localeIdentifier: String = "zh-CN",
        outputMode: DecomposeOutputMode = .extraction,
        availableTopicNames: [String] = []
    ) {
        self.requestID = requestID
        self.sourceDocumentID = sourceDocumentID
        self.chunkID = chunkID
        self.outputMode = outputMode
        self.contextBefore = contextBefore
        self.ownedMarkdown = markdown
        self.contextAfter = contextAfter
        self.ownedStartOffset = ownedStartOffset
        self.ownedEndOffset = ownedEndOffset
        self.localeIdentifier = localeIdentifier
        self.availableTopicNames = availableTopicNames
    }
}

struct CandidateDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let ordinal: Int
    let question: String
    let sourceBackedAnswerMaterial: String
    let sourceAnchors: [SourceAnchor]
    /// The exact existing Topic selected during question generation.
    /// It is optional only for backwards-compatible decoding of old responses;
    /// production requests with a topic whitelist validate it as required.
    let topicName: String?

    init(
        id: UUID,
        ordinal: Int,
        question: String,
        sourceBackedAnswerMaterial: String,
        sourceAnchors: [SourceAnchor],
        topicName: String? = nil
    ) {
        self.id = id
        self.ordinal = ordinal
        self.question = question
        self.sourceBackedAnswerMaterial = sourceBackedAnswerMaterial
        self.sourceAnchors = sourceAnchors
        self.topicName = topicName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let rawID = DecomposeResponseDecoder.string(in: container, keys: ["id", "candidateID", "candidateId"])
        id = rawID.flatMap(UUID.init(uuidString:)) ?? UUID()
        ordinal = DecomposeResponseDecoder.int(in: container, keys: ["ordinal", "order", "index"]) ?? 0
        question = DecomposeResponseDecoder.string(
            in: container,
            keys: ["question", "questionText", "prompt", "title"]
        ) ?? ""
        sourceBackedAnswerMaterial = DecomposeResponseDecoder.string(
            in: container,
            keys: ["sourceBackedAnswerMaterial", "sourceBackedMaterial", "answerMaterial", "answer", "material"]
        ) ?? ""
        sourceAnchors = DecomposeResponseDecoder.anchors(
            in: container,
            keys: ["sourceAnchors", "anchors", "sources"]
        )
        topicName = DecomposeResponseDecoder.string(
            in: container,
            keys: ["topicName", "topic", "tag", "category"]
        )
    }
}

struct DecomposeResponse: Codable, Equatable, Sendable {
    let candidates: [CandidateDraft]
    let completionStatus: AICompletionStatus

    init(candidates: [CandidateDraft], completionStatus: AICompletionStatus) {
        self.candidates = candidates
        self.completionStatus = completionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let rawCandidates = try DecomposeResponseDecoder.candidates(
            in: container,
            keys: ["candidates", "questions", "items"]
        )
        completionStatus = try DecomposeResponseDecoder.status(in: container)

        var normalizedCandidates: [CandidateDraft] = []
        normalizedCandidates.reserveCapacity(rawCandidates.count)
        var usedIDs = Set<UUID>()
        var lastOrdinal = -1

        for (index, candidate) in rawCandidates.enumerated() {
            var candidateID = candidate.id
            while !usedIDs.insert(candidateID).inserted {
                candidateID = UUID()
            }
            let ordinal: Int
            if candidate.ordinal >= 0, candidate.ordinal > lastOrdinal {
                ordinal = candidate.ordinal
            } else {
                ordinal = max(index, lastOrdinal + 1)
            }
            lastOrdinal = ordinal
            normalizedCandidates.append(
                CandidateDraft(
                    id: candidateID,
                    ordinal: ordinal,
                    question: candidate.question,
                    sourceBackedAnswerMaterial: candidate.sourceBackedAnswerMaterial,
                    sourceAnchors: candidate.sourceAnchors,
                    topicName: candidate.topicName
                )
            )
        }
        candidates = normalizedCandidates
    }
}

struct ReferenceAnswerRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let sourceDocumentID: UUID
    let question: String
    let sourceBackedMaterial: String
    let localeIdentifier: String

    init(
        requestID: UUID = UUID(),
        sourceDocumentID: UUID,
        question: String,
        sourceBackedMaterial: String,
        localeIdentifier: String = "zh-CN"
    ) {
        self.requestID = requestID
        self.sourceDocumentID = sourceDocumentID
        self.question = question
        self.sourceBackedMaterial = sourceBackedMaterial
        self.localeIdentifier = localeIdentifier
    }
}

struct ReferenceAnswerResponse: Codable, Equatable, Sendable {
    let answerText: String
    let keyPoints: [String]
    let modelID: String
    let promptVersion: String
    let completionStatus: AICompletionStatus

    init(
        answerText: String,
        keyPoints: [String],
        modelID: String,
        promptVersion: String,
        completionStatus: AICompletionStatus
    ) {
        self.answerText = answerText
        self.keyPoints = keyPoints
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.completionStatus = completionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        answerText = DecomposeResponseDecoder.string(
            in: container,
            keys: ["answerText", "fullScoreAnswer", "referenceAnswer", "answer"]
        ) ?? ""
        modelID = DecomposeResponseDecoder.string(
            in: container,
            keys: ["modelID", "modelId", "model"]
        ) ?? ""
        promptVersion = DecomposeResponseDecoder.string(
            in: container,
            keys: ["promptVersion", "prompt_version"]
        ) ?? PromptCatalog.referenceAnswerVersion
        completionStatus = (try? DecomposeResponseDecoder.status(in: container)) ?? .complete

        let keyPointsKey = AnyCodingKey("keyPoints")
        if let values = try? container.decode([String].self, forKey: keyPointsKey) {
            keyPoints = values
        } else if let value = try? container.decode(String.self, forKey: keyPointsKey) {
            keyPoints = value
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            keyPoints = []
        }
    }
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

/// The first, intentionally small evaluation response. Keeping this contract
/// separate from the detailed feedback response lets the UI show the score as
/// soon as the provider has finished the short judgment.
struct EvaluationScoreRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let question: String
    let referenceAnswer: String
    let sourceBackedMaterial: String
    let rawText: String
    let rubric: EvaluationRubric

    init(
        requestID: UUID = UUID(),
        question: String,
        referenceAnswer: String,
        sourceBackedMaterial: String,
        rawText: String,
        rubric: EvaluationRubric = .seniorSoftwareEngineer
    ) {
        self.requestID = requestID
        self.question = question
        self.referenceAnswer = referenceAnswer
        self.sourceBackedMaterial = sourceBackedMaterial
        self.rawText = rawText
        self.rubric = rubric
    }

    func asEvaluationRequest() -> EvaluationRequest {
        EvaluationRequest(
            requestID: requestID,
            question: question,
            referenceAnswer: referenceAnswer.isEmpty ? sourceBackedMaterial : referenceAnswer,
            rawText: rawText,
            polishedText: rawText,
            introducedClaims: [],
            rubric: rubric
        )
    }
}

struct EvaluationScoreDimension: Codable, Equatable, Sendable {
    let key: ScoreDimension
    let score: Int
}

struct EvaluationScoreResponse: Codable, Equatable, Sendable {
    let scorable: Bool
    let notScorableReason: String?
    let dimensions: [EvaluationScoreDimension]
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
        dimensions: [EvaluationScoreDimension],
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
        self.confidence = confidence
        self.scoreRange = scoreRange
        self.warnings = warnings
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.rubricVersion = rubricVersion
        self.completionStatus = completionStatus
    }

    private enum CodingKeys: String, CodingKey {
        case scorable, notScorableReason, dimensions, confidence, scoreRange, warnings
        case modelID, promptVersion, rubricVersion, completionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scorable = try container.decode(Bool.self, forKey: .scorable)
        let reason = try container.decodeIfPresent(String.self, forKey: .notScorableReason)
        notScorableReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : reason
        dimensions = try container.decode([FlexibleEvaluationScoreDimension].self, forKey: .dimensions).map(\.value)
        let decodedConfidence = try container.decode(Double.self, forKey: .confidence)
        confidence = decodedConfidence > 1 && decodedConfidence <= 100 ? decodedConfidence / 100 : decodedConfidence
        scoreRange = try container.decode(ScoreRange.self, forKey: .scoreRange)
        if let decodedWarnings = try? container.decodeIfPresent([String].self, forKey: .warnings) {
            warnings = decodedWarnings
        } else if let warning = try? container.decodeIfPresent(String.self, forKey: .warnings) {
            warnings = [warning]
        } else {
            warnings = []
        }
        modelID = try container.decode(String.self, forKey: .modelID)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        rubricVersion = try container.decode(String.self, forKey: .rubricVersion)
        completionStatus = try container.decode(AICompletionStatus.self, forKey: .completionStatus)
    }
}

struct EvaluationFeedbackRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let question: String
    let referenceAnswer: String
    let sourceBackedMaterial: String
    let rawText: String
    let scores: [EvaluationScoreDimension]
    let rubric: EvaluationRubric

    init(
        requestID: UUID = UUID(),
        question: String,
        referenceAnswer: String,
        sourceBackedMaterial: String,
        rawText: String,
        scores: [EvaluationScoreDimension],
        rubric: EvaluationRubric = .seniorSoftwareEngineer
    ) {
        self.requestID = requestID
        self.question = question
        self.referenceAnswer = referenceAnswer
        self.sourceBackedMaterial = sourceBackedMaterial
        self.rawText = rawText
        self.scores = scores
        self.rubric = rubric
    }

    func asEvaluationRequest() -> EvaluationRequest {
        EvaluationRequest(
            requestID: requestID,
            question: question,
            referenceAnswer: referenceAnswer.isEmpty ? sourceBackedMaterial : referenceAnswer,
            rawText: rawText,
            polishedText: rawText,
            introducedClaims: [],
            rubric: rubric
        )
    }
}

struct EvaluationFeedbackDimension: Codable, Equatable, Sendable {
    let key: ScoreDimension
    let evidence: [EvaluationEvidence]
    let missedPoints: [String]
    let feedback: String

    init(
        key: ScoreDimension,
        evidence: [EvaluationEvidence],
        missedPoints: [String],
        feedback: String
    ) {
        self.key = key
        self.evidence = evidence
        self.missedPoints = missedPoints
        self.feedback = feedback
    }

    private enum CodingKeys: String, CodingKey {
        case key, evidence, missedPoints, feedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawKey = try? container.decode(String.self, forKey: .key),
           let key = FlexibleEvaluationDimension.canonicalDimension(rawKey) {
            self.key = key
        } else {
            let keys = try decoder.container(keyedBy: AnyCodingKey.self)
            guard let keyField = keys.allKeys.first(where: {
                FlexibleEvaluationDimension.canonicalDimension($0.stringValue) != nil
            }), let key = FlexibleEvaluationDimension.canonicalDimension(keyField.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .key,
                    in: container,
                    debugDescription: "Evaluation feedback dimension has no recognized key"
                )
            }
            self.key = key
        }
        let decodedFeedback = (try? container.decode(String.self, forKey: .feedback)) ?? ""
        feedback = decodedFeedback

        // DeepSeek-compatible models sometimes collapse a one-item array into
        // a scalar string even when JSON mode is enabled. Normalize both
        // forms here so a valid quote is not discarded before the strict
        // rawText containment validator runs.
        if let decodedEvidence = try? container.decode([EvaluationEvidence].self, forKey: .evidence) {
            evidence = decodedEvidence
        } else if let evidenceStrings = try? container.decode([String].self, forKey: .evidence) {
            evidence = evidenceStrings.map {
                EvaluationEvidence(
                    quote: $0,
                    explanation: decodedFeedback.isEmpty ? "引用自用户回答。" : decodedFeedback
                )
            }
        } else if let evidenceString = try? container.decode(String.self, forKey: .evidence),
                  !evidenceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            evidence = [EvaluationEvidence(
                quote: evidenceString,
                explanation: decodedFeedback.isEmpty ? "引用自用户回答。" : decodedFeedback
            )]
        } else {
            evidence = []
        }

        if let decodedMissedPoints = try? container.decode([String].self, forKey: .missedPoints) {
            missedPoints = decodedMissedPoints
        } else if let missedPoint = try? container.decode(String.self, forKey: .missedPoints),
                  !missedPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missedPoints = [missedPoint]
        } else {
            missedPoints = []
        }
    }
}

struct EvaluationFeedbackResponse: Codable, Equatable, Sendable {
    let dimensions: [EvaluationFeedbackDimension]
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
        dimensions: [EvaluationFeedbackDimension],
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
        case dimensions, factualErrors, strengths, gapsAndErrors, improvements
        case polishOnlyClaims, confidence, scoreRange, warnings
        case modelID, promptVersion, rubricVersion, completionStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dimensions = try container.decode([EvaluationFeedbackDimension].self, forKey: .dimensions)
        factualErrors = try container.decodeIfPresent([FactualError].self, forKey: .factualErrors) ?? []
        strengths = try Self.decodeStringArray(container, key: .strengths)
        gapsAndErrors = try Self.decodeStringArray(container, key: .gapsAndErrors)
        improvements = try Self.decodeStringArray(container, key: .improvements)
        polishOnlyClaims = try Self.decodeStringArray(container, key: .polishOnlyClaims)
        let decodedConfidence = try container.decode(Double.self, forKey: .confidence)
        confidence = decodedConfidence > 1 && decodedConfidence <= 100 ? decodedConfidence / 100 : decodedConfidence
        scoreRange = try container.decode(ScoreRange.self, forKey: .scoreRange)
        warnings = try Self.decodeStringArray(container, key: .warnings)
        modelID = try container.decode(String.self, forKey: .modelID)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        rubricVersion = try container.decode(String.self, forKey: .rubricVersion)
        completionStatus = try container.decode(AICompletionStatus.self, forKey: .completionStatus)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dimensions, forKey: .dimensions)
        try container.encode(factualErrors, forKey: .factualErrors)
        try container.encode(strengths, forKey: .strengths)
        try container.encode(gapsAndErrors, forKey: .gapsAndErrors)
        try container.encode(improvements, forKey: .improvements)
        try container.encode(polishOnlyClaims, forKey: .polishOnlyClaims)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(scoreRange, forKey: .scoreRange)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(promptVersion, forKey: .promptVersion)
        try container.encode(rubricVersion, forKey: .rubricVersion)
        try container.encode(completionStatus, forKey: .completionStatus)
    }

    private static func decodeStringArray(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> [String] {
        if let array = try? container.decodeIfPresent([String].self, forKey: key) {
            return array
        }
        if let single = try? container.decodeIfPresent(String.self, forKey: key) {
            return [single]
        }
        return []
    }

    func asEvaluationResponse(scores: [EvaluationScoreDimension]) -> EvaluationResponse {
        let scoreMap = Dictionary(uniqueKeysWithValues: scores.map { ($0.key, $0.score) })
        return EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: dimensions.map {
                EvaluationDimension(
                    key: $0.key,
                    score: scoreMap[$0.key] ?? 0,
                    evidence: $0.evidence,
                    missedPoints: $0.missedPoints,
                    feedback: $0.feedback
                )
            },
            factualErrors: factualErrors,
            strengths: strengths,
            gapsAndErrors: gapsAndErrors,
            improvements: improvements,
            polishOnlyClaims: polishOnlyClaims,
            confidence: confidence,
            scoreRange: scoreRange,
            warnings: warnings,
            modelID: modelID,
            promptVersion: promptVersion,
            rubricVersion: rubricVersion,
            completionStatus: completionStatus
        )
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

    init(statement: String, explanation: String, referenceBasis: String) {
        self.statement = statement
        self.explanation = explanation
        self.referenceBasis = referenceBasis
    }

    private enum CodingKeys: String, CodingKey {
        case statement, explanation, referenceBasis
    }

    init(from decoder: Decoder) throws {
        // DeepSeek-compatible models sometimes collapse factualErrors into an
        // array of plain strings instead of objects. Normalize those entries
        // so a valid structured response is not discarded before the strict
        // validator runs.
        if let object = try? decoder.container(keyedBy: CodingKeys.self) {
            statement = try object.decodeIfPresent(String.self, forKey: .statement) ?? ""
            explanation = try object.decodeIfPresent(String.self, forKey: .explanation) ?? ""
            referenceBasis = try object.decodeIfPresent(String.self, forKey: .referenceBasis) ?? ""
            return
        }
        let string = try decoder.singleValueContainer().decode(String.self)
        statement = string
        explanation = ""
        referenceBasis = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(statement, forKey: .statement)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(referenceBasis, forKey: .referenceBasis)
    }
}

struct ScoreRange: Codable, Equatable, Sendable {
    let low: Int
    let high: Int

    init(low: Int, high: Int) {
        self.low = low
        self.high = high
    }

    init(from decoder: Decoder) throws {
        if let values = try? decoder.singleValueContainer().decode([Int].self),
           values.count >= 2 {
            low = Self.normalize(values[0])
            high = Self.normalize(values[1])
            return
        }

        if let rangeString = try? decoder.singleValueContainer().decode(String.self) {
            let integers = rangeString
                .split { !$0.isNumber }
                .compactMap { Int($0) }
            if integers.count >= 2 {
                low = Self.normalize(integers[0])
                high = Self.normalize(integers[1])
                return
            }
            if let single = integers.first {
                low = Self.normalize(single)
                high = Self.normalize(single)
                return
            }
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "ScoreRange string did not contain numeric bounds"
                )
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLow = try container.decodeIfPresent(Int.self, forKey: .low)
            ?? container.decode(Int.self, forKey: .min)
        let decodedHigh = try container.decodeIfPresent(Int.self, forKey: .high)
            ?? container.decode(Int.self, forKey: .max)
        low = Self.normalize(decodedLow)
        high = Self.normalize(decodedHigh)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(low, forKey: .low)
        try container.encode(high, forKey: .high)
    }

    private enum CodingKeys: String, CodingKey {
        case low, high, min, max
    }

    private static func normalize(_ value: Int) -> Int {
        value <= 5 ? value * 20 : value
    }
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

    fileprivate static func canonicalDimension(_ rawValue: String) -> ScoreDimension? {
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
        case "technicaldepth", "depthofknowledge", "reasoning", "reasoningdepth", "depth":
            return .reasoning
        case "clarity", "clarityofexpression", "structure", "structureclarity":
            return .structure
        case "tradeoffs", "application", "applicationtradeoffs", "practicalapplication", "codecorrectness", "implementation":
            return .tradeoffs
        case "conciseness", "innovationandinsight", "precision", "precisionconciseness", "brevity":
            return .precision
        case "problemsolving":
            return .coverage
        default:
            return nil
        }
    }
}

private struct FlexibleEvaluationScoreDimension: Decodable {
    let value: EvaluationScoreDimension

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let keyField = AnyCodingKey("key")
        let scoreField = AnyCodingKey("score")

        if let rawKey = try? container.decode(String.self, forKey: keyField),
           let key = FlexibleEvaluationDimension.canonicalDimension(rawKey),
           let score = try? container.decode(Int.self, forKey: scoreField) {
            value = EvaluationScoreDimension(key: key, score: score <= 5 ? score * 20 : score)
            return
        }

        guard let dimensionField = container.allKeys.first(where: {
            FlexibleEvaluationDimension.canonicalDimension($0.stringValue) != nil
        }),
        let key = FlexibleEvaluationDimension.canonicalDimension(dimensionField.stringValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: keyField,
                in: container,
                debugDescription: "Evaluation score dimension has no recognized key"
            )
        }
        let rawScore = try container.decode(Int.self, forKey: dimensionField)
        value = EvaluationScoreDimension(key: key, score: rawScore <= 5 ? rawScore * 20 : rawScore)
    }
}

private enum DecomposeResponseDecoder {
    static func string(
        in container: KeyedDecodingContainer<AnyCodingKey>,
        keys: [String]
    ) -> String? {
        for rawKey in keys {
            let key = AnyCodingKey(rawKey)
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    static func int(
        in container: KeyedDecodingContainer<AnyCodingKey>,
        keys: [String]
    ) -> Int? {
        for rawKey in keys {
            let key = AnyCodingKey(rawKey)
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(String.self, forKey: key),
               let integer = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return integer
            }
            if let value = try? container.decode(Double.self, forKey: key) {
                return Int(value)
            }
        }
        return nil
    }

    static func uuid(
        in container: KeyedDecodingContainer<AnyCodingKey>,
        keys: [String]
    ) -> UUID? {
        guard let rawValue = string(in: container, keys: keys) else { return nil }
        return UUID(uuidString: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func anchors(
        in container: KeyedDecodingContainer<AnyCodingKey>,
        keys: [String]
    ) -> [SourceAnchor] {
        for rawKey in keys {
            let key = AnyCodingKey(rawKey)
            if let values = try? container.decode([SourceAnchor].self, forKey: key) {
                return values
            }
            if let value = try? container.decode(SourceAnchor.self, forKey: key) {
                return [value]
            }
        }
        return []
    }

    static func candidates(
        in container: KeyedDecodingContainer<AnyCodingKey>,
        keys: [String]
    ) throws -> [CandidateDraft] {
        for rawKey in keys {
            let key = AnyCodingKey(rawKey)
            guard container.contains(key) else { continue }
            if let values = try? container.decode([CandidateDraft].self, forKey: key) {
                return values
            }
            if let value = try? container.decode(CandidateDraft.self, forKey: key) {
                return [value]
            }
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Decompose candidates could not be decoded"
            )
        }
        throw DecodingError.keyNotFound(
            AnyCodingKey("candidates"),
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Decompose response has no candidates field"
            )
        )
    }

    static func status(
        in container: KeyedDecodingContainer<AnyCodingKey>
    ) throws -> AICompletionStatus {
        for rawKey in ["completionStatus", "status", "completion"] {
            let key = AnyCodingKey(rawKey)
            guard container.contains(key) else { continue }
            return try container.decode(AICompletionStatus.self, forKey: key)
        }
        throw DecodingError.keyNotFound(
            AnyCodingKey("completionStatus"),
            DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Decompose response has no completion status"
            )
        )
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
