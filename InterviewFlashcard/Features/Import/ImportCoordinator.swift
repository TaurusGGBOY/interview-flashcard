import CryptoKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ImportCoordinator {
    struct BatchPlan: Equatable, Sendable {
        let sourceIndex: Int
        let candidateCount: Int
        var containsSingleSourceDocument: Bool { true }
    }

    enum ImportError: Error, Equatable {
        case runNotFound(UUID)
        case invalidUTF8(String)
        case malformedPersistedChunk(UUID)
        case malformedCandidateAnchors(UUID)
        case invalidDecomposeResponse(UUID)
        case invalidRefineResponse(UUID)
        case invalidReferenceAnswer(UUID, FullScoreAnswerQualityPolicy.Rejection)
        case missingOthersTopic
    }

    private struct ChunkContextEnvelope: Codable, Equatable {
        let contextBefore: String
        let contextAfter: String
        let headingPath: [String]
        let ownedStartOffset: Int
        let ownedEndOffset: Int
        let ownedStartLine: Int
        let ownedEndLine: Int
    }

    private struct StagedCandidateMutation {
        let primary: QuestionCandidateRecord
        let duplicates: [QuestionCandidateRecord]
        let card: RefinedCardDraft
        let sourceAnchor: String
    }

    private struct ActivationPlan {
        let candidate: QuestionCandidateRecord
        let keyPointsJSON: String
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let aiClient: any AIClient
    @ObservationIgnored private let chunker: MarkdownChunker
    @ObservationIgnored private let diagnostics: DiagnosticStateExporter
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let importsDirectory: URL
    @ObservationIgnored private let now: @Sendable () -> Date

    private(set) var isWorking = false
    private(set) var lastStartedRunIDs: [UUID] = []

    init(
        context: ModelContext,
        aiClient: any AIClient,
        chunker: MarkdownChunker = .init(),
        diagnostics: DiagnosticStateExporter = .init(isEnabled: false),
        fileManager: FileManager = .default,
        importsDirectory: URL? = nil,
        retryDelayNanoseconds: UInt64 = 300_000_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        if aiClient is RetryingAIClient {
            self.aiClient = aiClient
        } else {
            self.aiClient = RetryingAIClient(
                base: aiClient,
                maximumRetries: 1,
                retryDelayNanoseconds: retryDelayNanoseconds
            )
        }
        self.chunker = chunker
        self.diagnostics = diagnostics
        self.fileManager = fileManager
        self.importsDirectory = importsDirectory ?? Self.defaultImportsDirectory(fileManager: fileManager)
        self.now = now
    }

    func start(urls: [URL]) async throws -> [UUID] {
        isWorking = true
        defer { isWorking = false }

        var runIDs: [UUID] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidUTF8(url.lastPathComponent)
            }
            let sourceID = UUID()
            let relativePath = try copyToApplicationSupport(
                data: data,
                fileName: url.lastPathComponent,
                sourceDocumentID: sourceID
            )
            let runID = try await createAndProcess(
                markdown: markdown,
                fileName: url.lastPathComponent,
                sourcePath: relativePath,
                sourceDocumentID: sourceID
            )
            runIDs.append(runID)
        }
        lastStartedRunIDs = runIDs
        return runIDs
    }

    @discardableResult
    func start(markdown: String, fileName: String) async throws -> UUID {
        isWorking = true
        defer { isWorking = false }
        let runID = try await createAndProcess(
            markdown: markdown,
            fileName: fileName,
            sourcePath: nil,
            sourceDocumentID: UUID()
        )
        lastStartedRunIDs = [runID]
        return runID
    }

    func continueRun(id: UUID) async throws {
        let runID = id
        let descriptor = FetchDescriptor<ImportRunRecord>(
            predicate: #Predicate { run in
                run.id == runID
            }
        )
        guard let run = try context.fetch(descriptor).first else {
            throw ImportError.runNotFound(id)
        }
        guard run.status != .active else { return }

        isWorking = true
        defer { isWorking = false }
        await process(run: run)
    }

    static func makeBatchPlan(candidateCounts: [Int], maximumBatchSize: Int = 50) -> [BatchPlan] {
        precondition(maximumBatchSize > 0)
        return candidateCounts.enumerated().flatMap { sourceIndex, count in
            guard count > 0 else { return [BatchPlan]() }
            var remaining = count
            var batches: [BatchPlan] = []
            while remaining > 0 {
                let size = min(remaining, maximumBatchSize)
                batches.append(BatchPlan(sourceIndex: sourceIndex, candidateCount: size))
                remaining -= size
            }
            return batches
        }
    }

    private func createAndProcess(
        markdown: String,
        fileName: String,
        sourcePath: String?,
        sourceDocumentID: UUID
    ) async throws -> UUID {
        let timestamp = now()
        let source = SourceDocumentRecord(
            id: sourceDocumentID,
            fileName: fileName,
            sourcePath: sourcePath,
            contentHash: SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined(),
            importerVersion: "markdown-ai-v1",
            importedAt: timestamp
        )
        let run = ImportRunRecord(
            status: .queued,
            createdAt: timestamp,
            updatedAt: timestamp,
            sourceDocument: source
        )
        context.insert(source)
        context.insert(run)

        let chunks = try chunker.chunks(markdown: markdown)
        let encoder = JSONEncoder()
        for chunk in chunks {
            let envelope = ChunkContextEnvelope(
                contextBefore: chunk.contextBefore,
                contextAfter: chunk.contextAfter,
                headingPath: chunk.headingPath,
                ownedStartOffset: chunk.ownedStartOffset,
                ownedEndOffset: chunk.ownedEndOffset,
                ownedStartLine: chunk.ownedStartLine,
                ownedEndLine: chunk.ownedEndLine
            )
            let envelopeData = try encoder.encode(envelope)
            let record = ImportChunkRecord(
                ordinal: chunk.ordinal,
                ownedMarkdown: chunk.ownedMarkdown,
                contextMarkdown: String(decoding: envelopeData, as: UTF8.self),
                sourceAnchor: "lines:\(chunk.ownedStartLine)-\(chunk.ownedEndLine);utf16:\(chunk.ownedStartOffset)-\(chunk.ownedEndOffset)",
                createdAt: timestamp,
                updatedAt: timestamp,
                importRun: run
            )
            context.insert(record)
        }
        try saveAndExport()
        await process(run: run)
        return run.id
    }

    private func process(run: ImportRunRecord) async {
        do {
            if run.chunks.contains(where: { $0.status != .completed }) {
                try await decompose(run: run)
            }
            if run.refinementBatches.isEmpty {
                try createRefinementBatches(run: run)
            }
            if run.refinementBatches.contains(where: { $0.status != .completed }) {
                try await refine(run: run)
            }
            try activate(run: run)
        } catch {
            context.rollback()
            run.status = .failed
            run.errorSummary = safeErrorSummary(error)
            run.updatedAt = now()
            do {
                try saveAndExport()
            } catch {
                assertionFailure("Unable to persist failed import state: \(error.localizedDescription)")
            }
        }
    }

    private func decompose(run: ImportRunRecord) async throws {
        run.status = .decomposing
        run.errorSummary = nil
        run.updatedAt = now()
        try saveAndExport()

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for chunk in run.chunks.sorted(by: { $0.ordinal < $1.ordinal }) where chunk.status != .completed {
            chunk.status = .processing
            chunk.errorSummary = nil
            chunk.updatedAt = now()
            try saveAndExport()

            do {
                guard let data = chunk.contextMarkdown.data(using: .utf8),
                      let envelope = try? decoder.decode(ChunkContextEnvelope.self, from: data) else {
                    throw ImportError.malformedPersistedChunk(chunk.id)
                }
                let request = DecomposeRequest(
                    sourceDocumentID: run.sourceDocument.id,
                    chunkID: chunk.id,
                    markdown: chunk.ownedMarkdown,
                    contextBefore: envelope.contextBefore,
                    contextAfter: envelope.contextAfter,
                    ownedStartOffset: envelope.ownedStartOffset,
                    ownedEndOffset: envelope.ownedEndOffset
                )
                let response = try await aiClient.decompose(request)
                try AIResponseValidator.validate(response, for: request)
                guard response.completionStatus == .complete,
                      response.candidates.allSatisfy({ draft in
                          !draft.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && !draft.sourceAnchors.isEmpty
                              && draft.sourceAnchors.allSatisfy {
                                  $0.sourceDocumentID == run.sourceDocument.id
                                      && $0.chunkID == chunk.id
                                      && $0.startOffset >= envelope.ownedStartOffset
                                      && $0.endOffset <= envelope.ownedEndOffset
                              }
                      }) else {
                    throw ImportError.invalidDecomposeResponse(chunk.id)
                }

                for draft in response.candidates {
                    let anchorData = try encoder.encode(draft.sourceAnchors)
                    context.insert(
                        QuestionCandidateRecord(
                            id: draft.id,
                            sourceOrder: chunk.ordinal * 1_000_000 + draft.ordinal,
                            questionText: draft.question,
                            proposedAnswerText: draft.sourceBackedAnswerMaterial,
                            sourceAnchor: String(decoding: anchorData, as: UTF8.self),
                            createdAt: now(),
                            importChunk: chunk
                        )
                    )
                }
                chunk.status = .completed
                chunk.updatedAt = now()
                try saveAndExport()
            } catch {
                context.rollback()
                chunk.status = .failed
                chunk.errorSummary = safeErrorSummary(error)
                chunk.updatedAt = now()
                try saveAndExport()
                throw error
            }
        }
    }

    private func createRefinementBatches(run: ImportRunRecord) throws {
        let candidates = run.chunks
            .flatMap(\.candidates)
            .sorted { $0.sourceOrder < $1.sourceOrder }
        let timestamp = now()
        for (ordinal, start) in stride(from: 0, to: candidates.count, by: 50).enumerated() {
            let end = min(start + 50, candidates.count)
            let batchCandidates = Array(candidates[start..<end])
            let batch = RefinementBatchRecord(
                ordinal: ordinal,
                candidateCount: batchCandidates.count,
                createdAt: timestamp,
                updatedAt: timestamp,
                importRun: run
            )
            context.insert(batch)
            for candidate in batchCandidates {
                candidate.refinementBatch = batch
            }
        }
        run.status = .refining
        run.updatedAt = timestamp
        try saveAndExport()
    }

    private func refine(run: ImportRunRecord) async throws {
        run.status = .refining
        run.errorSummary = nil
        run.updatedAt = now()
        try saveAndExport()

        let topicNames = try context.fetch(FetchDescriptor<TopicRecord>())
            .map(\.name)
            .sorted()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for batch in run.refinementBatches.sorted(by: { $0.ordinal < $1.ordinal }) where batch.status != .completed {
            batch.status = .processing
            batch.errorSummary = nil
            batch.updatedAt = now()
            try saveAndExport()

            do {
                let records = batch.candidates.sorted { $0.sourceOrder < $1.sourceOrder }
                guard records.count <= 50 else {
                    throw ImportError.invalidRefineResponse(batch.id)
                }
                let drafts = try records.map { record -> CandidateDraft in
                    guard let data = record.sourceAnchor.data(using: .utf8),
                          let anchors = try? decoder.decode([SourceAnchor].self, from: data) else {
                        throw ImportError.malformedCandidateAnchors(record.id)
                    }
                    return CandidateDraft(
                        id: record.id,
                        ordinal: record.sourceOrder,
                        question: record.questionText,
                        sourceBackedAnswerMaterial: record.proposedAnswerText,
                        sourceAnchors: anchors
                    )
                }
                let response = try await aiClient.refine(
                    RefineRequest(
                        sourceDocumentID: run.sourceDocument.id,
                        batchID: batch.id,
                        candidates: drafts,
                        availableTopicNames: topicNames
                    )
                )
                try AIResponseValidator.validate(response)
                try stage(
                    response: response,
                    records: records,
                    batch: batch,
                    decoder: decoder,
                    encoder: encoder
                )
                batch.status = .completed
                batch.updatedAt = now()
                try saveAndExport()
            } catch {
                context.rollback()
                batch.status = .failed
                batch.errorSummary = safeErrorSummary(error)
                batch.updatedAt = now()
                try saveAndExport()
                throw error
            }
        }
    }

    private func stage(
        response: RefineResponse,
        records: [QuestionCandidateRecord],
        batch: RefinementBatchRecord,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) throws {
        guard response.completionStatus == .complete else {
            throw ImportError.invalidRefineResponse(batch.id)
        }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let anchorsByID = try Dictionary(uniqueKeysWithValues: records.map { record in
            guard let data = record.sourceAnchor.data(using: .utf8),
                  let anchors = try? decoder.decode([SourceAnchor].self, from: data) else {
                throw ImportError.malformedCandidateAnchors(record.id)
            }
            return (record.id, Set(anchors))
        })
        var consumed = Set<UUID>()
        var mutations: [StagedCandidateMutation] = []
        mutations.reserveCapacity(response.cards.count)

        for card in response.cards {
            let mergedIDs = Set(card.mergedCandidateIDs)
            let allowedAnchors = mergedIDs.reduce(into: Set<SourceAnchor>()) { result, id in
                result.formUnion(anchorsByID[id] ?? [])
            }
            guard !mergedIDs.isEmpty,
                  card.mergedCandidateIDs.count == mergedIDs.count,
                  mergedIDs.isSubset(of: Set(byID.keys)),
                  consumed.isDisjoint(with: mergedIDs),
                  !card.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !card.fullScoreAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !card.sourceAnchors.isEmpty,
                  Set(card.sourceAnchors).isSubset(of: allowedAnchors),
                  card.sourceAnchors.allSatisfy({ $0.sourceDocumentID == batch.importRun.sourceDocument.id }) else {
                throw ImportError.invalidRefineResponse(batch.id)
            }
            let mergedRecords = card.mergedCandidateIDs.compactMap { byID[$0] }
                .sorted { $0.sourceOrder < $1.sourceOrder }
            guard let primary = mergedRecords.first else {
                throw ImportError.invalidRefineResponse(batch.id)
            }
            switch FullScoreAnswerQualityPolicy.assess(card.fullScoreAnswer) {
            case .success:
                break
            case let .failure(rejection):
                throw ImportError.invalidReferenceAnswer(batch.id, rejection)
            }
            let sourceAnchor = String(decoding: try encoder.encode(card.sourceAnchors), as: UTF8.self)
            consumed.formUnion(mergedIDs)
            mutations.append(
                StagedCandidateMutation(
                    primary: primary,
                    duplicates: Array(mergedRecords.dropFirst()),
                    card: card,
                    sourceAnchor: sourceAnchor
                )
            )
        }

        guard consumed == Set(byID.keys) else {
            throw ImportError.invalidRefineResponse(batch.id)
        }

        // Apply candidate mutations only after every card in this batch has
        // passed structural, source-anchor, and full-score answer validation.
        for mutation in mutations {
            mutation.primary.questionText = mutation.card.question
            mutation.primary.proposedAnswerText = mutation.card.fullScoreAnswer
            mutation.primary.proposedTopicName = mutation.card.topicName
            mutation.primary.sourceAnchor = mutation.sourceAnchor
            mutation.primary.status = .refined
            for duplicate in mutation.duplicates {
                duplicate.status = .duplicateWithinBatch
            }
        }
    }

    private func activate(run: ImportRunRecord) throws {
        guard run.status != .active else { return }
        let allBatchesComplete = run.refinementBatches.allSatisfy { $0.status == .completed }
        guard allBatchesComplete else {
            throw ImportError.invalidRefineResponse(run.id)
        }

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        guard let others = topics.first(where: { $0.systemKind == .others }) else {
            throw ImportError.missingOthersTopic
        }
        let topicByName = Dictionary(uniqueKeysWithValues: topics.map { ($0.name, $0) })
        let refinedCandidates = run.chunks
            .flatMap(\.candidates)
            .filter { $0.status == .refined }
            .sorted { $0.sourceOrder < $1.sourceOrder }

        let encoder = JSONEncoder()
        var activationPlans: [ActivationPlan] = []
        activationPlans.reserveCapacity(refinedCandidates.count)
        for candidate in refinedCandidates {
            let keyPoints: [String]
            switch FullScoreAnswerQualityPolicy.assess(candidate.proposedAnswerText) {
            case let .success(points):
                keyPoints = points
            case let .failure(rejection):
                throw ImportError.invalidReferenceAnswer(run.id, rejection)
            }
            let keyPointsJSON = String(decoding: try encoder.encode(keyPoints), as: UTF8.self)
            activationPlans.append(
                ActivationPlan(candidate: candidate, keyPointsJSON: keyPointsJSON)
            )
        }

        run.status = .activating
        run.updatedAt = now()
        try saveAndExport()

        let timestamp = now()
        for plan in activationPlans {
            let candidate = plan.candidate
            let topic = candidate.proposedTopicName.flatMap { topicByName[$0] } ?? others
            let card = QuestionCardRecord(
                questionText: candidate.questionText,
                sourceAnchor: candidate.sourceAnchor,
                createdAt: timestamp,
                updatedAt: timestamp,
                activatedAt: timestamp,
                topic: topic,
                sourceDocument: run.sourceDocument
            )
            context.insert(card)
            context.insert(
                ReferenceAnswerVersionRecord(
                    version: 1,
                    answerText: candidate.proposedAnswerText,
                    keyPointsJSON: plan.keyPointsJSON,
                    origin: .aiGenerated,
                    promptVersion: PromptCatalog.refineVersion,
                    createdAt: timestamp,
                    question: card
                )
            )
        }
        run.status = .active
        run.errorSummary = nil
        run.updatedAt = timestamp
        try saveAndExport()
    }

    private func saveAndExport() throws {
        try context.save()
        try diagnostics.export(from: context)
    }

    private func copyToApplicationSupport(
        data: Data,
        fileName: String,
        sourceDocumentID: UUID
    ) throws -> String {
        let directory = importsDirectory.appendingPathComponent(sourceDocumentID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let destination = directory.appendingPathComponent(safeName, isDirectory: false)
        try data.write(to: destination, options: [.atomic])
        return destination.path.replacingOccurrences(of: importsDirectory.path + "/", with: "")
    }

    private func safeErrorSummary(_ error: Error) -> String {
        if let error = error as? AIError {
            return String(describing: error)
        }
        if let error = error as? ImportError {
            if case let .invalidReferenceAnswer(_, rejection) = error {
                return rejection.description
            }
            return String(describing: error)
        }
        return String(describing: type(of: error))
    }

    private static func defaultImportsDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
    }
}
