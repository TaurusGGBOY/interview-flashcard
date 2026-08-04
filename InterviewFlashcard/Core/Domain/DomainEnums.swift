import Foundation

enum SystemTopicKind: String, Codable, CaseIterable, Sendable {
    case others
}

enum ImportRunStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case chunking
    case decomposing
    case refining
    case activating
    case active
    case failed
}

enum ImportChunkStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case processing
    case completed
    case failed
}

enum QuestionCandidateStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case refined
    case duplicateWithinBatch
    case invalid
}

enum BatchStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case skipped
}

enum AnswerInputMode: String, Codable, CaseIterable, Sendable {
    case typed
    case voice
}

enum AttemptProcessingStatus: String, Codable, CaseIterable, Sendable {
    case saved
    case polishing
    case evaluating
    case completed
    case failed
}

enum EvaluationStatus: String, Codable, CaseIterable, Sendable {
    case completed
    case failed
    case discarded
}

enum ReferenceAnswerOrigin: String, Codable, CaseIterable, Sendable {
    case aiGenerated
    case userEdited
}

enum ReclassificationRunStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case completed
    case completedWithFailures
}
