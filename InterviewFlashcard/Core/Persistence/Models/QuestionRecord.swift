import Foundation
import SwiftData

@Model
final class QuestionCardRecord {
    @Attribute(.unique) var id: UUID
    var questionText: String
    var sourceAnchor: String
    var createdAt: Date
    var updatedAt: Date
    var activatedAt: Date
    var trashedAt: Date?
    var topic: TopicRecord
    var sourceDocument: SourceDocumentRecord

    @Relationship(deleteRule: .cascade, inverse: \ReferenceAnswerVersionRecord.question)
    var referenceAnswers: [ReferenceAnswerVersionRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \AnswerAttemptRecord.question)
    var attempts: [AnswerAttemptRecord] = []

    var isTrashed: Bool { trashedAt != nil }

    init(
        id: UUID = UUID(),
        questionText: String,
        sourceAnchor: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        activatedAt: Date = Date(),
        trashedAt: Date? = nil,
        topic: TopicRecord,
        sourceDocument: SourceDocumentRecord
    ) {
        self.id = id
        self.questionText = questionText
        self.sourceAnchor = sourceAnchor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activatedAt = activatedAt
        self.trashedAt = trashedAt
        self.topic = topic
        self.sourceDocument = sourceDocument
    }
}

@Model
final class ReferenceAnswerVersionRecord {
    @Attribute(.unique) var id: UUID
    var version: Int
    var answerText: String
    var keyPointsJSON: String
    var originRaw: String
    var modelID: String?
    var promptVersion: String?
    var createdAt: Date
    var question: QuestionCardRecord

    var origin: ReferenceAnswerOrigin {
        get { ReferenceAnswerOrigin(rawValue: originRaw) ?? .aiGenerated }
        set { originRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        version: Int,
        answerText: String,
        keyPointsJSON: String = "[]",
        origin: ReferenceAnswerOrigin = .aiGenerated,
        modelID: String? = nil,
        promptVersion: String? = nil,
        createdAt: Date = Date(),
        question: QuestionCardRecord
    ) {
        self.id = id
        self.version = version
        self.answerText = answerText
        self.keyPointsJSON = keyPointsJSON
        self.originRaw = origin.rawValue
        self.modelID = modelID
        self.promptVersion = promptVersion
        self.createdAt = createdAt
        self.question = question
    }
}
