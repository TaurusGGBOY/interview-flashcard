import Foundation
import SwiftData

@MainActor
struct ReclassificationService {
    static let maximumBatchSize = 50

    struct Progress: Equatable, Sendable {
        let completedBatches: Int
        let totalBatches: Int
    }

    struct Summary: Equatable, Sendable {
        let totalCards: Int
        let succeededBatches: Int
        let failedBatches: Int
        let remainingOthersCards: Int
        let fatalErrorMessage: String?

        var completedBatches: Int {
            succeededBatches + failedBatches
        }
    }

    private enum ServiceError: Error, Sendable {
        case missingOthersTopic
        case incompleteAssignments
        case unknownTopic(String)
        case truncatedResponse
    }

    private struct WorkItem: Sendable {
        let ordinal: Int
        let batchID: UUID
        let cardIDs: Set<UUID>
        let request: ReclassifyRequest
    }

    private let aiClient: any AIClient
    private let diagnostics: DiagnosticStateExporter
    private let now: @Sendable () -> Date

    init(
        aiClient: any AIClient,
        diagnostics: DiagnosticStateExporter = DiagnosticStateExporter(isEnabled: false),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.aiClient = aiClient
        self.diagnostics = diagnostics
        self.now = now
    }

    func runAllOthers(
        context: ModelContext,
        onProgress: ((Progress) -> Void)? = nil
    ) async -> Summary {
        do {
            return try await execute(context: context, onProgress: onProgress)
        } catch {
            return Summary(
                totalCards: 0,
                succeededBatches: 0,
                failedBatches: 0,
                remainingOthersCards: (try? activeOthers(in: context).count) ?? 0,
                fatalErrorMessage: safeErrorSummary(error)
            )
        }
    }

    private func execute(
        context: ModelContext,
        onProgress: ((Progress) -> Void)?
    ) async throws -> Summary {
        let snapshot = try activeOthers(in: context)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
            .sorted(by: TopicService.libraryOrder)
        let availableTopicNames = topics.map(\.name)
        let cardBatches = snapshot.chunked(maximumSize: Self.maximumBatchSize)
        let timestamp = now()
        let run = ReclassificationRunRecord(
            status: cardBatches.isEmpty ? .completed : .running,
            totalCards: snapshot.count,
            startedAt: timestamp,
            completedAt: cardBatches.isEmpty ? timestamp : nil
        )
        context.insert(run)

        let batchRecords = cardBatches.enumerated().map { offset, cards in
            let record = ReclassificationBatchRecord(
                ordinal: offset + 1,
                cardCount: cards.count,
                createdAt: timestamp,
                updatedAt: timestamp,
                run: run
            )
            context.insert(record)
            return record
        }
        try saveAndExport(context)

        let persistedTopics = try context.fetch(FetchDescriptor<TopicRecord>())
        guard persistedTopics.contains(where: { $0.systemKind == .others }) else {
            throw ServiceError.missingOthersTopic
        }
        let topicByName = Dictionary(
            uniqueKeysWithValues: persistedTopics
                .filter { availableTopicNames.contains($0.name) }
                .map { ($0.name, $0) }
        )

        var workItems: [WorkItem] = []
        workItems.reserveCapacity(cardBatches.count)
        for (offset, cards) in cardBatches.enumerated() {
            let batchRecord = batchRecords[offset]
            let request = ReclassifyRequest(
                batchID: batchRecord.id,
                cards: cards.map(makeRequestCard),
                availableTopicNames: availableTopicNames
            )
            workItems.append(
                WorkItem(
                    ordinal: offset,
                    batchID: batchRecord.id,
                    cardIDs: Set(cards.map(\.id)),
                    request: request
                )
            )
            batchRecord.status = .processing
            batchRecord.errorSummary = nil
            batchRecord.updatedAt = now()
        }
        try saveAndExport(context)

        let client = aiClient
        let results = await BoundedAITaskRunner.run(inputs: workItems) { item in
            let response = try await client.reclassify(item.request)
            try AIResponseValidator.validate(
                response,
                for: item.request,
                enforceTopicWhitelist: true
            )
            guard response.completionStatus == .complete else {
                throw ServiceError.truncatedResponse
            }
            return response
        }

        var succeededBatches = 0
        var failedBatches = 0
        let batchesByID = Dictionary(uniqueKeysWithValues: batchRecords.map { ($0.id, $0) })
        for result in results {
            let item = workItems[result.index]
            guard let batchRecord = batchesByID[item.batchID] else { continue }
            let cards = cardBatches[item.ordinal]
            do {
                guard let response = result.value else {
                    throw ServiceError.incompleteAssignments
                }
                let assignmentByCardID = try validatedAssignments(response, cardIDs: item.cardIDs)
                let updatedAt = now()
                for card in cards {
                    guard let requestedTopic = assignmentByCardID[card.id],
                          let destination = topicByName[requestedTopic] else {
                        throw ServiceError.unknownTopic(
                            assignmentByCardID[card.id] ?? "<missing>"
                        )
                    }
                    card.topic = destination
                }
                batchRecord.status = .completed
                batchRecord.errorSummary = nil
                batchRecord.updatedAt = updatedAt
                run.reclassifiedCards += cards.count
                succeededBatches += 1
            } catch {
                batchRecord.status = .failed
                let errorSummary = result.errorDescription ?? safeErrorSummary(error)
                batchRecord.errorSummary = errorSummary
#if DEBUG
                print(
                    "IF_RECLASS_BATCH_FAILED batch=\(item.batchID.uuidString) " +
                    "topics=\(item.request.availableTopicNames) " +
                    "error=\(errorSummary)"
                )
#endif
                batchRecord.updatedAt = now()
                run.failedCards += cards.count
                failedBatches += 1
            }
            try saveAndExport(context)
            onProgress?(
                Progress(
                    completedBatches: succeededBatches + failedBatches,
                    totalBatches: cardBatches.count
                )
            )
        }

        run.status = failedBatches == 0 ? .completed : .completedWithFailures
        run.completedAt = now()
        try saveAndExport(context)

        return Summary(
            totalCards: snapshot.count,
            succeededBatches: succeededBatches,
            failedBatches: failedBatches,
            remainingOthersCards: try activeOthers(in: context).count,
            fatalErrorMessage: nil
        )
    }

    private func activeOthers(in context: ModelContext) throws -> [QuestionCardRecord] {
        try context.fetch(FetchDescriptor<QuestionCardRecord>())
            .filter { !$0.isTrashed && $0.topic.systemKind == .others }
    }

    private func makeRequestCard(_ card: QuestionCardRecord) -> ReclassificationCard {
        ReclassificationCard(
            id: card.id,
            question: card.questionText,
            fullScoreAnswer: card.referenceAnswers.max(by: { $0.version < $1.version })?.answerText ?? ""
        )
    }

    private func validatedAssignments(
        _ response: ReclassifyResponse,
        cardIDs: Set<UUID>
    ) throws -> [UUID: String] {
        guard response.completionStatus == .complete else {
            throw ServiceError.truncatedResponse
        }

        let responseIDs = response.assignments.map(\.cardID)
        guard response.assignments.count == cardIDs.count,
              Set(responseIDs).count == responseIDs.count,
              Set(responseIDs) == cardIDs
        else {
            throw ServiceError.incompleteAssignments
        }
        return Dictionary(uniqueKeysWithValues: response.assignments.map { ($0.cardID, $0.topicName) })
    }

    private func saveAndExport(_ context: ModelContext) throws {
        try context.save()
        try? diagnostics.export(from: context)
    }

    private func safeErrorSummary(_ error: Error) -> String {
        if let error = error as? AIError {
            return String(describing: error)
        }
        if let error = error as? ServiceError {
            return String(describing: error)
        }
        return String(describing: type(of: error))
    }
}

private extension Array {
    func chunked(maximumSize: Int) -> [[Element]] {
        precondition(maximumSize > 0)
        return stride(from: 0, to: count, by: maximumSize).map { start in
            Array(self[start..<Swift.min(start + maximumSize, count)])
        }
    }
}
