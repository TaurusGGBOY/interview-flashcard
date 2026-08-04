import Foundation
import SwiftData

@Model
final class ImportRunRecord {
    @Attribute(.unique) var id: UUID
    var statusRaw: String
    var errorSummary: String?
    var createdAt: Date
    var updatedAt: Date
    var sourceDocument: SourceDocumentRecord

    @Relationship(deleteRule: .cascade, inverse: \ImportChunkRecord.importRun)
    var chunks: [ImportChunkRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \RefinementBatchRecord.importRun)
    var refinementBatches: [RefinementBatchRecord] = []

    var status: ImportRunStatus {
        get { ImportRunStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        status: ImportRunStatus = .queued,
        errorSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceDocument: SourceDocumentRecord
    ) {
        self.id = id
        self.statusRaw = status.rawValue
        self.errorSummary = errorSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceDocument = sourceDocument
    }
}

@Model
final class ImportChunkRecord {
    @Attribute(.unique) var id: UUID
    var ordinal: Int
    var ownedMarkdown: String
    var contextMarkdown: String
    var sourceAnchor: String
    var statusRaw: String
    var errorSummary: String?
    var createdAt: Date
    var updatedAt: Date
    var importRun: ImportRunRecord

    @Relationship(deleteRule: .cascade, inverse: \QuestionCandidateRecord.importChunk)
    var candidates: [QuestionCandidateRecord] = []

    var status: ImportChunkStatus {
        get { ImportChunkStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ordinal: Int,
        ownedMarkdown: String,
        contextMarkdown: String,
        sourceAnchor: String,
        status: ImportChunkStatus = .pending,
        errorSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        importRun: ImportRunRecord
    ) {
        self.id = id
        self.ordinal = ordinal
        self.ownedMarkdown = ownedMarkdown
        self.contextMarkdown = contextMarkdown
        self.sourceAnchor = sourceAnchor
        self.statusRaw = status.rawValue
        self.errorSummary = errorSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importRun = importRun
    }
}

@Model
final class QuestionCandidateRecord {
    @Attribute(.unique) var id: UUID
    var sourceOrder: Int
    var questionText: String
    var proposedAnswerText: String
    var sourceAnchor: String
    var proposedTopicName: String?
    var statusRaw: String
    var createdAt: Date
    var importChunk: ImportChunkRecord
    var refinementBatch: RefinementBatchRecord?

    var status: QuestionCandidateStatus {
        get { QuestionCandidateStatus(rawValue: statusRaw) ?? .invalid }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        sourceOrder: Int,
        questionText: String,
        proposedAnswerText: String,
        sourceAnchor: String,
        proposedTopicName: String? = nil,
        status: QuestionCandidateStatus = .pending,
        createdAt: Date = Date(),
        importChunk: ImportChunkRecord,
        refinementBatch: RefinementBatchRecord? = nil
    ) {
        self.id = id
        self.sourceOrder = sourceOrder
        self.questionText = questionText
        self.proposedAnswerText = proposedAnswerText
        self.sourceAnchor = sourceAnchor
        self.proposedTopicName = proposedTopicName
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.importChunk = importChunk
        self.refinementBatch = refinementBatch
    }
}

@Model
final class RefinementBatchRecord {
    @Attribute(.unique) var id: UUID
    var ordinal: Int
    var candidateCount: Int
    var statusRaw: String
    var errorSummary: String?
    var createdAt: Date
    var updatedAt: Date
    var importRun: ImportRunRecord

    @Relationship(inverse: \QuestionCandidateRecord.refinementBatch)
    var candidates: [QuestionCandidateRecord] = []

    var status: BatchStatus {
        get { BatchStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ordinal: Int,
        candidateCount: Int,
        status: BatchStatus = .pending,
        errorSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        importRun: ImportRunRecord
    ) {
        self.id = id
        self.ordinal = ordinal
        self.candidateCount = candidateCount
        self.statusRaw = status.rawValue
        self.errorSummary = errorSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importRun = importRun
    }
}
