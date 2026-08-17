import Foundation
import SwiftData

enum AppModelContainer {
    @MainActor
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(AppSchemaV1.models)
        let configuration = ModelConfiguration(
            "InterviewFlashcard",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func bootstrapOthers(context: ModelContext, now: Date = Date()) throws {
        // Keep this bootstrap query deliberately simple. iOS 27's SwiftData
        // beta has a runtime trap for `fetchCount` with an optional-string
        // predicate on an in-memory store; filtering the already tiny topic
        // table in memory is deterministic and avoids that framework bug.
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        guard !topics.contains(where: { $0.systemKind == .others }) else {
            return
        }

        context.insert(
            TopicRecord(
                id: TopicRecord.othersID,
                name: "Others",
                systemKind: .others,
                createdAt: now,
                updatedAt: now
            )
        )
        try context.save()
    }
}
