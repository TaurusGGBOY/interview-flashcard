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
    case ready
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
    case extracted
    case refined
    case duplicateWithinBatch
    case invalid

    /// Candidates in these states can still become question cards. Pending
    /// is the normal state between background extraction and the user's
    /// confirmation in the file-import flow.
    var isActivationEligible: Bool {
        switch self {
        case .pending, .extracted, .refined:
            true
        case .duplicateWithinBatch, .invalid:
            false
        }
    }
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
    case scoring
    case feedback
    case referenceAnswer
    case polishing
    case evaluating
    case completed
    case failed
}

enum EvaluationStatus: String, Codable, CaseIterable, Sendable {
    case scoring
    case feedback
    case completed
    case failed
    case discarded
}

enum ReferenceAnswerOrigin: String, Codable, CaseIterable, Sendable {
    case aiGenerated
    case userEdited
    case jsonImported
}

enum ReclassificationRunStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case completed
    case completedWithFailures
}
