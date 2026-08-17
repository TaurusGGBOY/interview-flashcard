import SwiftData
import Foundation

enum TestModelContainer {
    // ModelContext does not retain its ModelContainer. Keep the containers
    // alive for the duration of the XCTest process so a shorthand
    // `make().mainContext` cannot leave a context backed by a deallocated
    // store (which traps on the first insert under iOS 27).
    @MainActor
    private static var retainedContainers: [ModelContainer] = []

    @MainActor
    static func make() throws -> ModelContainer {
        // Keep the concrete type list here. Xcode 27 beta can trap while
        // lazily materializing a type-erased VersionedSchema array from an
        // XCTest host, although the same models work when listed directly.
        let schema = Schema([
            TopicRecord.self,
            SourceDocumentRecord.self,
            ImportRunRecord.self,
            ImportChunkRecord.self,
            QuestionCandidateRecord.self,
            RefinementBatchRecord.self,
            QuestionCardRecord.self,
            ReferenceAnswerVersionRecord.self,
            AnswerAttemptRecord.self,
            PolishResultRecord.self,
            EvaluationRecord.self,
            AudioAssetRecord.self,
            ReclassificationRunRecord.self,
            ReclassificationBatchRecord.self,
        ])
        let configuration = ModelConfiguration(
            "InterviewFlashcardTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container
    }
}
