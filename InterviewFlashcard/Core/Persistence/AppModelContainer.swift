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
        let rawKind = SystemTopicKind.others.rawValue
        let descriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { topic in
                topic.systemKindRaw == rawKind
            }
        )

        guard try context.fetchCount(descriptor) == 0 else {
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
