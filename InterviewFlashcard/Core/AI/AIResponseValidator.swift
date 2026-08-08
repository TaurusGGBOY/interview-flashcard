import Foundation

enum AIResponseValidationError: Error, Equatable, Sendable {
    case truncated
    case emptyField(String)
    case duplicateID(String)
    case invalidAnchor
    case unknownTopic(String)
    case invalidBatchSize(Int)
    case missingDimension(ScoreDimension)
    case duplicateDimension(ScoreDimension)
    case unexpectedDimension(ScoreDimension)
    case scoreOutOfRange(ScoreDimension, Int)
    case invalidRubricWeights
    case invalidConfidence(Double)
    case invalidScoreRange
    case evidenceNotFound(String)
    case polishOnlyEvidenceCredited(ScoreDimension, String)
    case invalidScorableState
    case promptVersionMismatch(expected: String, actual: String)
    case rubricVersionMismatch(expected: String, actual: String)
}

enum AIResponseValidator {
    static func validate(_ response: DecomposeResponse, for request: DecomposeRequest? = nil) throws {
        try requireComplete(response.completionStatus)
        var ids = Set<UUID>()
        var lastOrdinal = -1
        for candidate in response.candidates {
            guard ids.insert(candidate.id).inserted else {
                throw AIResponseValidationError.duplicateID(candidate.id.uuidString)
            }
            try requireText(candidate.question, field: "candidate.question")
            try requireText(candidate.sourceBackedAnswerMaterial, field: "candidate.sourceBackedAnswerMaterial")
            guard candidate.ordinal >= 0, candidate.ordinal > lastOrdinal else {
                throw AIResponseValidationError.invalidResponseOrdinal
            }
            lastOrdinal = candidate.ordinal
            try validateAnchors(candidate.sourceAnchors, request: request)
        }
    }

    static func validate(_ response: RefineResponse, allowedTopics: Set<String>? = nil) throws {
        try requireComplete(response.completionStatus)
        var cardIDs = Set<UUID>()
        var consumedCandidateIDs = Set<UUID>()
        for card in response.cards {
            guard cardIDs.insert(card.id).inserted else {
                throw AIResponseValidationError.duplicateID(card.id.uuidString)
            }
            guard !card.mergedCandidateIDs.isEmpty else {
                throw AIResponseValidationError.emptyField("card.mergedCandidateIDs")
            }
            for candidateID in card.mergedCandidateIDs {
                guard consumedCandidateIDs.insert(candidateID).inserted else {
                    throw AIResponseValidationError.duplicateID(candidateID.uuidString)
                }
            }
            try requireText(card.question, field: "card.question")
            try requireText(card.fullScoreAnswer, field: "card.fullScoreAnswer")
            try requireText(card.topicName, field: "card.topicName")
            if let allowedTopics, !allowedTopics.contains(card.topicName) {
                throw AIResponseValidationError.unknownTopic(card.topicName)
            }
            try validateAnchors(card.sourceAnchors, request: nil)
        }
    }

    static func validate(
        _ response: ReclassifyResponse,
        for request: ReclassifyRequest,
        enforceTopicWhitelist: Bool = false
    ) throws {
        try requireComplete(response.completionStatus)
        guard request.cards.count <= 50 else {
            throw AIResponseValidationError.invalidBatchSize(request.cards.count)
        }
        let requestedIDs = Set(request.cards.map(\.id))
        let allowedTopics = Set(request.availableTopicNames)
        var assignedIDs = Set<UUID>()
        for assignment in response.assignments {
            guard requestedIDs.contains(assignment.cardID),
                  assignedIDs.insert(assignment.cardID).inserted else {
                throw AIResponseValidationError.duplicateID(assignment.cardID.uuidString)
            }
            try requireText(assignment.topicName, field: "reclassification.topicName")
            guard !enforceTopicWhitelist || allowedTopics.contains(assignment.topicName) else {
                throw AIResponseValidationError.unknownTopic(assignment.topicName)
            }
        }
        guard assignedIDs == requestedIDs else {
            throw AIResponseValidationError.invalidScorableState
        }
    }

    static func validate(_ response: PolishResponse, rawText: String) throws {
        try requireComplete(response.completionStatus)
        try requireText(rawText, field: "polish.rawText")
        try requireText(response.polishedText, field: "polish.polishedText")
        for edit in response.edits {
            try requireText(edit.original, field: "polish.edit.original")
            try requireText(edit.replacement, field: "polish.edit.replacement")
            try requireText(edit.reason, field: "polish.edit.reason")
        }
        for claim in response.introducedClaims {
            try requireText(claim.text, field: "polish.introducedClaim.text")
            guard contains(response.polishedText, quote: claim.text) else {
                throw AIResponseValidationError.evidenceNotFound(claim.text)
            }
        }
        try requireText(response.modelID, field: "polish.modelID")
        try requireText(response.promptVersion, field: "polish.promptVersion")
    }

    static func validate(
        _ response: EvaluationResponse,
        rubric: EvaluationRubric,
        rawText: String,
        polishedText: String,
        expectedPromptVersion: String = PromptCatalog.evaluateVersion
    ) throws {
        try requireComplete(response.completionStatus)
        let expectedDimensions = Set(rubric.dimensions.map(\.key))
        guard rubric.dimensions.reduce(0, { $0 + $1.weight }) == 100,
              rubric.dimensions.allSatisfy({ (0...100).contains($0.weight) }),
              expectedDimensions.count == rubric.dimensions.count else {
            throw AIResponseValidationError.invalidRubricWeights
        }
        guard response.promptVersion == expectedPromptVersion else {
            throw AIResponseValidationError.promptVersionMismatch(
                expected: expectedPromptVersion,
                actual: response.promptVersion
            )
        }
        guard response.rubricVersion == rubric.version else {
            throw AIResponseValidationError.rubricVersionMismatch(
                expected: rubric.version,
                actual: response.rubricVersion
            )
        }
        try validateEvaluation(
            response,
            expectedDimensions: expectedDimensions,
            rawText: rawText,
            polishedText: polishedText
        )
        guard response.scorable else {
            return
        }
        guard let total = rubric.total(for: response.dimensions) else {
            throw AIResponseValidationError.invalidScorableState
        }
        if total != 100 {
            try requireNonEmptyList(response.gapsAndErrors, field: "evaluation.gapsAndErrors")
            try requireNonEmptyList(response.improvements, field: "evaluation.improvements")
        }
    }

    static func validate(
        _ response: EvaluationResponse,
        rubric: ScoringRubric,
        rawText: String,
        polishedText: String
    ) throws {
        guard rubric.weights.values.reduce(0, +) == 100 else {
            throw AIResponseValidationError.invalidRubricWeights
        }
        try validateEvaluation(
            response,
            expectedDimensions: Set(rubric.dimensions),
            rawText: rawText,
            polishedText: polishedText
        )
    }

    private static func validateEvaluation(
        _ response: EvaluationResponse,
        expectedDimensions: Set<ScoreDimension>,
        rawText: String,
        polishedText: String
    ) throws {
        guard (0...1).contains(response.confidence) else {
            throw AIResponseValidationError.invalidConfidence(response.confidence)
        }
        guard (0...100).contains(response.scoreRange.low),
              (0...100).contains(response.scoreRange.high),
              response.scoreRange.low <= response.scoreRange.high else {
            throw AIResponseValidationError.invalidScoreRange
        }

        try requireText(response.modelID, field: "evaluation.modelID")
        try requireText(response.promptVersion, field: "evaluation.promptVersion")
        try requireText(response.rubricVersion, field: "evaluation.rubricVersion")
        for (index, error) in response.factualErrors.enumerated() {
            try requireText(error.statement, field: "evaluation.factualErrors[\(index)].statement")
            try requireText(error.explanation, field: "evaluation.factualErrors[\(index)].explanation")
            try requireText(error.referenceBasis, field: "evaluation.factualErrors[\(index)].referenceBasis")
        }

        if !response.scorable {
            guard response.dimensions.isEmpty,
                  !(response.notScorableReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
                throw AIResponseValidationError.invalidScorableState
            }
            return
        }
        guard response.notScorableReason == nil else {
            throw AIResponseValidationError.invalidScorableState
        }

        var seen = Set<ScoreDimension>()
        for dimension in response.dimensions {
            guard expectedDimensions.contains(dimension.key) else {
                throw AIResponseValidationError.unexpectedDimension(dimension.key)
            }
            guard seen.insert(dimension.key).inserted else {
                throw AIResponseValidationError.duplicateDimension(dimension.key)
            }
            guard (0...100).contains(dimension.score) else {
                throw AIResponseValidationError.scoreOutOfRange(dimension.key, dimension.score)
            }
            try requireText(dimension.feedback, field: "evaluation.feedback.\(dimension.key.rawValue)")
            guard !dimension.evidence.isEmpty else {
                throw AIResponseValidationError.emptyField("evaluation.evidence.\(dimension.key.rawValue)")
            }
            for evidence in dimension.evidence {
                try requireText(evidence.quote, field: "evaluation.evidence.quote")
                try requireText(evidence.explanation, field: "evaluation.evidence.explanation")
                guard contains(rawText, quote: evidence.quote) else {
                    if (dimension.key == .correctness || dimension.key == .coverage),
                       contains(polishedText, quote: evidence.quote) {
                        throw AIResponseValidationError.polishOnlyEvidenceCredited(dimension.key, evidence.quote)
                    }
                    throw AIResponseValidationError.evidenceNotFound(evidence.quote)
                }
            }
            if dimension.score < 100 {
                try requireNonEmptyList(
                    dimension.missedPoints,
                    field: "evaluation.missedPoints.\(dimension.key.rawValue)"
                )
            }
        }

        for missing in expectedDimensions.subtracting(seen) {
            throw AIResponseValidationError.missingDimension(missing)
        }
    }

    private static func validateAnchors(
        _ anchors: [SourceAnchor],
        request: DecomposeRequest?
    ) throws {
        guard !anchors.isEmpty else {
            throw AIResponseValidationError.invalidAnchor
        }
        for anchor in anchors {
            guard anchor.startOffset >= 0,
                  anchor.endOffset > anchor.startOffset,
                  !anchor.exactQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIResponseValidationError.invalidAnchor
            }
            if let request {
                guard anchor.sourceDocumentID == request.sourceDocumentID,
                      anchor.chunkID == request.chunkID,
                      anchor.startOffset >= request.ownedStartOffset,
                      anchor.startOffset < request.ownedEndOffset,
                      contains(request.ownedMarkdown, quote: anchor.exactQuote) else {
                    throw AIResponseValidationError.invalidAnchor
                }
            }
        }
    }

    private static func requireComplete(_ status: AICompletionStatus) throws {
        guard status == .complete else {
            throw AIResponseValidationError.truncated
        }
    }

    private static func requireText(_ text: String, field: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIResponseValidationError.emptyField(field)
        }
    }

    private static func requireNonEmptyList(_ values: [String], field: String) throws {
        guard values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw AIResponseValidationError.emptyField(field)
        }
    }

    private static func contains(_ text: String, quote: String) -> Bool {
        let normalizedText = normalizeEvidence(text)
        let normalizedQuote = normalizeEvidence(quote)
        return !normalizedQuote.isEmpty && normalizedText.contains(normalizedQuote)
    }

    private static func normalizeEvidence(_ text: String) -> String {
        let punctuationMap: [Character: Character] = [
            "，": ",", "。": ".", "！": "!", "？": "?", "：": ":", "；": ";",
            "（": "(", "）": ")", "【": "[", "】": "]", "“": "\"", "”": "\"",
            "‘": "'", "’": "'"
        ]
        let mapped = String(text.map { punctuationMap[$0] ?? $0 })
        let folded = mapped.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private extension AIResponseValidationError {
    static var invalidResponseOrdinal: AIResponseValidationError {
        .emptyField("candidate.ordinal")
    }
}
