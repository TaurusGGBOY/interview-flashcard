import Foundation
import SwiftData

@MainActor
struct DiagnosticStateExporter {
    struct Snapshot: Codable, Equatable {
        struct Topic: Codable, Equatable {
            let id: UUID
            let name: String
            let systemKind: String?
        }

        struct Card: Codable, Equatable {
            let id: UUID
            let topicID: UUID
            let sourceDocumentID: UUID
            let questionText: String
            let referenceAnswerCount: Int
            let attemptCount: Int
            let trashedAt: Date?
        }

        struct ImportRun: Codable, Equatable {
            let id: UUID
            let sourceDocumentID: UUID
            let status: String
            let chunkCount: Int
            let batchCount: Int
            let errorSummary: String?
        }

        struct Attempt: Codable, Equatable {
            let id: UUID
            let questionID: UUID
            let rawText: String
            let inputMode: String
            let processingStatus: String
            let submittedAt: Date
        }

        struct PolishResult: Codable, Equatable {
            let id: UUID
            let attemptID: UUID
            let revision: Int
            let polishedText: String
        }

        struct Evaluation: Codable, Equatable {
            let id: UUID
            let attemptID: UUID
            let totalScore: Int?
            let status: String
            let dimensions: DimensionScores
        }

        struct AudioAsset: Codable, Equatable {
            let id: UUID
            let attemptID: UUID
            let relativePath: String
            let duration: Double
        }

        struct ReclassificationRun: Codable, Equatable {
            let id: UUID
            let status: String
            let totalCards: Int
            let reclassifiedCards: Int
            let failedCards: Int
        }

        let schemaVersion: Int
        let topics: [Topic]
        let cards: [Card]
        let importRuns: [ImportRun]
        let attempts: [Attempt]
        let polishResults: [PolishResult]
        let evaluations: [Evaluation]
        let audioAssets: [AudioAsset]
        let reclassificationRuns: [ReclassificationRun]
    }

    let isEnabled: Bool
    let destinationURL: URL

    init(
        isEnabled: Bool,
        destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        #if DEBUG
        self.isEnabled = isEnabled
        #else
        self.isEnabled = false
        #endif
        self.destinationURL = destinationURL ?? Self.defaultDestination(fileManager: fileManager)
    }

    func export(from context: ModelContext, fileManager: FileManager = .default) throws {
        guard isEnabled else { return }

        let snapshot = try makeSnapshot(from: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    func makeSnapshot(from context: ModelContext) throws -> Snapshot {
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let importRuns = try context.fetch(FetchDescriptor<ImportRunRecord>())
        let attempts = try context.fetch(FetchDescriptor<AnswerAttemptRecord>())
        let polishResults = try context.fetch(FetchDescriptor<PolishResultRecord>())
        let evaluations = try context.fetch(FetchDescriptor<EvaluationRecord>())
        let audioAssets = try context.fetch(FetchDescriptor<AudioAssetRecord>())
        let reclassificationRuns = try context.fetch(FetchDescriptor<ReclassificationRunRecord>())

        return Snapshot(
            schemaVersion: 1,
            topics: topics
                .map { .init(id: $0.id, name: $0.name, systemKind: $0.systemKindRaw) }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            cards: cards
                .map {
                    .init(
                        id: $0.id,
                        topicID: $0.topic.id,
                        sourceDocumentID: $0.sourceDocument.id,
                        questionText: $0.questionText,
                        referenceAnswerCount: $0.referenceAnswers.count,
                        attemptCount: $0.attempts.count,
                        trashedAt: $0.trashedAt
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            importRuns: importRuns
                .map {
                    .init(
                        id: $0.id,
                        sourceDocumentID: $0.sourceDocument.id,
                        status: $0.statusRaw,
                        chunkCount: $0.chunks.count,
                        batchCount: $0.refinementBatches.count,
                        errorSummary: $0.errorSummary
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            attempts: attempts
                .map {
                    .init(
                        id: $0.id,
                        questionID: $0.question.id,
                        rawText: $0.rawText,
                        inputMode: $0.inputModeRaw,
                        processingStatus: $0.processingStatusRaw,
                        submittedAt: $0.submittedAt
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            polishResults: polishResults
                .map { .init(id: $0.id, attemptID: $0.attempt.id, revision: $0.revision, polishedText: $0.polishedText) }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            evaluations: evaluations
                .map {
                    .init(
                        id: $0.id,
                        attemptID: $0.attempt.id,
                        totalScore: $0.totalScore,
                        status: $0.statusRaw,
                        dimensions: $0.dimensionScores
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            audioAssets: audioAssets
                .map { .init(id: $0.id, attemptID: $0.attempt.id, relativePath: $0.relativePath, duration: $0.duration) }
                .sorted { $0.id.uuidString < $1.id.uuidString },
            reclassificationRuns: reclassificationRuns
                .map {
                    .init(
                        id: $0.id,
                        status: $0.statusRaw,
                        totalCards: $0.totalCards,
                        reclassifiedCards: $0.reclassifiedCards,
                        failedCards: $0.failedCards
                    )
                }
                .sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    private static func defaultDestination(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }
}
