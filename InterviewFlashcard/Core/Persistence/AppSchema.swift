import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
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
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
