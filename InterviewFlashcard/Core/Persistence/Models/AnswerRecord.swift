import Foundation
import SwiftData

@Model
final class AnswerAttemptRecord {
    @Attribute(.unique) var id: UUID
    var questionTextSnapshot: String
    var referenceAnswerTextSnapshot: String
    var referenceAnswerVersion: Int
    var rawText: String
    var inputModeRaw: String
    var processingStatusRaw: String
    var failureSummary: String?
    var startedAt: Date
    var submittedAt: Date
    var question: QuestionCardRecord

    @Relationship(deleteRule: .cascade, inverse: \PolishResultRecord.attempt)
    var polishResults: [PolishResultRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \EvaluationRecord.attempt)
    var evaluations: [EvaluationRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \AudioAssetRecord.attempt)
    var audioAsset: AudioAssetRecord?

    var inputMode: AnswerInputMode {
        get { AnswerInputMode(rawValue: inputModeRaw) ?? .typed }
        set { inputModeRaw = newValue.rawValue }
    }

    var processingStatus: AttemptProcessingStatus {
        get { AttemptProcessingStatus(rawValue: processingStatusRaw) ?? .failed }
        set { processingStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        questionTextSnapshot: String,
        referenceAnswerTextSnapshot: String,
        referenceAnswerVersion: Int,
        rawText: String,
        inputMode: AnswerInputMode,
        processingStatus: AttemptProcessingStatus = .saved,
        failureSummary: String? = nil,
        startedAt: Date,
        submittedAt: Date,
        question: QuestionCardRecord
    ) {
        self.id = id
        self.questionTextSnapshot = questionTextSnapshot
        self.referenceAnswerTextSnapshot = referenceAnswerTextSnapshot
        self.referenceAnswerVersion = referenceAnswerVersion
        self.rawText = rawText
        self.inputModeRaw = inputMode.rawValue
        self.processingStatusRaw = processingStatus.rawValue
        self.failureSummary = failureSummary
        self.startedAt = startedAt
        self.submittedAt = submittedAt
        self.question = question
    }
}

@Model
final class PolishResultRecord {
    @Attribute(.unique) var id: UUID
    var revision: Int
    var inputText: String
    var polishedText: String
    var editSummaryJSON: String
    var suspectedASRErrorsJSON: String
    var introducedClaimsJSON: String
    var needsUserReview: Bool
    var promptVersion: String
    var modelID: String
    var createdAt: Date
    var attempt: AnswerAttemptRecord

    init(
        id: UUID = UUID(),
        revision: Int,
        inputText: String,
        polishedText: String,
        editSummaryJSON: String = "[]",
        suspectedASRErrorsJSON: String = "[]",
        introducedClaimsJSON: String = "[]",
        needsUserReview: Bool = false,
        promptVersion: String,
        modelID: String,
        createdAt: Date = Date(),
        attempt: AnswerAttemptRecord
    ) {
        self.id = id
        self.revision = revision
        self.inputText = inputText
        self.polishedText = polishedText
        self.editSummaryJSON = editSummaryJSON
        self.suspectedASRErrorsJSON = suspectedASRErrorsJSON
        self.introducedClaimsJSON = introducedClaimsJSON
        self.needsUserReview = needsUserReview
        self.promptVersion = promptVersion
        self.modelID = modelID
        self.createdAt = createdAt
        self.attempt = attempt
    }
}

@Model
final class EvaluationRecord {
    @Attribute(.unique) var id: UUID
    var totalScore: Int?
    var correctnessScore: Int
    var coverageScore: Int
    var reasoningScore: Int
    var structureScore: Int
    var tradeoffsScore: Int
    var precisionScore: Int
    var strengthsJSON: String
    var nextAnswerPlanJSON: String
    var factualErrorsJSON: String
    var feedbackJSON: String
    var confidence: String
    var statusRaw: String
    var provider: String
    var modelID: String
    var promptVersion: String
    var rubricVersion: String
    var createdAt: Date
    var attempt: AnswerAttemptRecord
    var polishResultID: UUID?

    var status: EvaluationStatus {
        get { EvaluationStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var dimensionScores: DimensionScores {
        DimensionScores(
            correctness: correctnessScore,
            coverage: coverageScore,
            reasoning: reasoningScore,
            structure: structureScore,
            tradeoffs: tradeoffsScore,
            precision: precisionScore
        )
    }

    init(
        id: UUID = UUID(),
        totalScore: Int?,
        scores: DimensionScores,
        strengthsJSON: String = "[]",
        nextAnswerPlanJSON: String = "[]",
        factualErrorsJSON: String = "[]",
        feedbackJSON: String = "{}",
        confidence: String,
        status: EvaluationStatus = .completed,
        provider: String,
        modelID: String,
        promptVersion: String,
        rubricVersion: String,
        createdAt: Date = Date(),
        attempt: AnswerAttemptRecord,
        polishResultID: UUID? = nil
    ) {
        self.id = id
        self.totalScore = totalScore
        self.correctnessScore = scores.correctness
        self.coverageScore = scores.coverage
        self.reasoningScore = scores.reasoning
        self.structureScore = scores.structure
        self.tradeoffsScore = scores.tradeoffs
        self.precisionScore = scores.precision
        self.strengthsJSON = strengthsJSON
        self.nextAnswerPlanJSON = nextAnswerPlanJSON
        self.factualErrorsJSON = factualErrorsJSON
        self.feedbackJSON = feedbackJSON
        self.confidence = confidence
        self.statusRaw = status.rawValue
        self.provider = provider
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.rubricVersion = rubricVersion
        self.createdAt = createdAt
        self.attempt = attempt
        self.polishResultID = polishResultID
    }
}

@Model
final class AudioAssetRecord {
    @Attribute(.unique) var id: UUID
    var relativePath: String
    var format: String
    var duration: Double
    var byteCount: Int64
    var checksum: String
    var transcriptionEngine: String
    var localeIdentifier: String
    var confidenceSummary: String?
    var createdAt: Date
    var attempt: AnswerAttemptRecord

    init(
        id: UUID = UUID(),
        relativePath: String,
        format: String = "m4a",
        duration: Double,
        byteCount: Int64,
        checksum: String,
        transcriptionEngine: String,
        localeIdentifier: String,
        confidenceSummary: String? = nil,
        createdAt: Date = Date(),
        attempt: AnswerAttemptRecord
    ) {
        self.id = id
        self.relativePath = relativePath
        self.format = format
        self.duration = duration
        self.byteCount = byteCount
        self.checksum = checksum
        self.transcriptionEngine = transcriptionEngine
        self.localeIdentifier = localeIdentifier
        self.confidenceSummary = confidenceSummary
        self.createdAt = createdAt
        self.attempt = attempt
    }
}
