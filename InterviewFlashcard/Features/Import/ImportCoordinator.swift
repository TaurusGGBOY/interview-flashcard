import CryptoKit
import Foundation
import Observation
import SwiftData

private enum InterviewQuestionPolicy {
    private static let chineseQuestionSignals = [
        "什么", "为什么", "为何", "如何", "怎么", "怎样", "哪些", "哪个", "是否", "能否",
        "区别", "差异", "优缺点", "原理", "机制", "作用", "场景", "实现", "设计", "排查",
        "解释", "比较", "对比"
    ]

    private static let englishQuestionSignals = Set([
        "what", "why", "how", "which", "when", "where", "whether", "explain", "describe",
        "compare", "difference", "design", "implement", "troubleshoot", "optimize", "use", "best"
    ])

    private static let kubernetesSignals = [
        "kubernetes", "k8s", "kubectl", "pod", "container", "cluster", "namespace", "deployment",
        "replicaset", "statefulset", "daemonset", "cronjob", "service", "ingress", "configmap",
        "secret", "rbac", "serviceaccount", "custom resource", "crd", "operator", "controller",
        "kubelet", "kube-proxy", "etcd", "helm", "kustomize", "networkpolicy", "network policy",
        "persistent volume", "persistentvolume", "pvc", "storageclass", "probe", "sidecar",
        "taint", "toleration", "affinity"
    ]

    static func accepts(_ rawQuestion: String) -> Bool {
        let question = rawQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*-•0123456789. "))
        guard question.count >= 3 else { return false }

        if question.contains("?") || question.contains("？") {
            return true
        }

        if chineseQuestionSignals.contains(where: { question.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        let words = question
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        return words.contains(where: englishQuestionSignals.contains)
    }

    static func normalizedTopicName(
        proposedTopicName: String?,
        question: String,
        material: String,
        othersName: String,
        availableTopicNames: [String]
    ) -> String? {
        guard let proposedTopicName else { return nil }
        guard TopicNameNormalization.key(proposedTopicName) == TopicNameNormalization.key(othersName) else {
            return proposedTopicName
        }
        guard let kubernetesTopic = availableTopicNames.first(where: isKubernetesTopicName) else {
            return proposedTopicName
        }

        let source = (question + "\n" + material).lowercased()
        guard kubernetesSignals.contains(where: { source.contains($0) }) else {
            return proposedTopicName
        }
        return kubernetesTopic
    }

    private static func isKubernetesTopicName(_ name: String) -> Bool {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return normalized.contains("kubernetes") || normalized == "k8s" || normalized.contains("k8s")
    }
}

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
        case invalidTextEncoding(String)
        case malformedPersistedChunk(UUID)
        case malformedCandidateAnchors(UUID)
        case invalidDecomposeResponse(UUID)
        case invalidRefineResponse(UUID)
        case missingOthersTopic
        case runNotReadyForConfirmation(UUID)
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

    private struct DecomposeWorkItem: Sendable {
        let ordinal: Int
        let chunkID: UUID
        let request: DecomposeRequest
        let ownedStartOffset: Int
        let ownedEndOffset: Int
        let sourceOrderBase: Int
    }

    private struct RefineWorkItem: Sendable {
        let ordinal: Int
        let batchID: UUID
        let request: RefineRequest
    }

    private struct CandidateMutationSnapshot {
        let questionText: String
        let proposedAnswerText: String
        let proposedTopicName: String?
        let sourceAnchor: String
        let status: QuestionCandidateStatus
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
    @ObservationIgnored private let singlePassLLMImport: Bool
    @ObservationIgnored private let refinementBatchSize: Int
    @ObservationIgnored private let aiConcurrency: Int
    @ObservationIgnored private let numberingService: QuestionNumberingService

    private static let fallbackDecomposeTargetCharacters = 4_000
    private static let fallbackDecomposeOverlapCharacters = 200

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
        singlePassLLMImport: Bool = false,
        refinementBatchSize: Int = 50,
        aiConcurrency: Int = 4,
        numberingService: QuestionNumberingService = QuestionNumberingService(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition((1...50).contains(refinementBatchSize))
        precondition((1...8).contains(aiConcurrency))
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
        self.singlePassLLMImport = singlePassLLMImport
        self.refinementBatchSize = refinementBatchSize
        self.aiConcurrency = aiConcurrency
        self.numberingService = numberingService
        self.now = now
    }

    func start(urls: [URL]) async throws -> [UUID] {
        isWorking = true
        defer { isWorking = false }

        var runIDs: [UUID] = []
        var runs: [ImportRunRecord] = []
        do {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url)
                let text = try decodeText(data, fileName: url.lastPathComponent)
                let sourceID = UUID()
                let relativePath = try copyToApplicationSupport(
                    data: data,
                    fileName: url.lastPathComponent,
                    sourceDocumentID: sourceID
                )
                let run = try createRun(
                    markdown: text,
                    fileName: url.lastPathComponent,
                    sourcePath: relativePath,
                    sourceDocumentID: sourceID
                )
                runIDs.append(run.id)
                runs.append(run)
            }
        } catch {
            // A later file can fail before the picker returns. Do not strand
            // already-persisted runs in queued state in that case.
            enqueueProcessing(runs)
            throw error
        }
        lastStartedRunIDs = runIDs
        enqueueProcessing(runs)
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
        guard run.status != .active, run.status != .ready else { return }

        isWorking = true
        defer { isWorking = false }
        await process(run: run)
    }

    /// Schedules a failed run for recovery without keeping the import screen
    /// attached to the potentially long-running AI request.
    func enqueueContinuation(id: UUID) throws {
        let runID = id
        let descriptor = FetchDescriptor<ImportRunRecord>(
            predicate: #Predicate { run in
                run.id == runID
            }
        )
        guard let run = try context.fetch(descriptor).first else {
            throw ImportError.runNotFound(id)
        }
        guard run.status == .failed else { return }
        run.status = .queued
        run.errorSummary = nil
        run.updatedAt = now()
        try saveAndExport()
        enqueueProcessing([run])
    }

    /// Commits every validated candidate in a ready run in one local
    /// transaction. It is intentionally separate from AI processing so a
    /// ready run can wait for an explicit user confirmation.
    func confirmImport(id: UUID) throws {
        let runID = id
        let descriptor = FetchDescriptor<ImportRunRecord>(
            predicate: #Predicate { run in
                run.id == runID
            }
        )
        guard let run = try context.fetch(descriptor).first else {
            throw ImportError.runNotFound(id)
        }
        guard run.status == .ready || run.status == .active else {
            throw ImportError.runNotReadyForConfirmation(id)
        }
        guard run.status != .active else { return }

        do {
            try activate(run: run)
        } catch {
            context.rollback()
            run.status = .ready
            run.errorSummary = safeErrorSummary(error)
            run.updatedAt = now()
            try? saveAndExport()
            throw error
        }
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
        let run = try createRun(
            markdown: markdown,
            fileName: fileName,
            sourcePath: sourcePath,
            sourceDocumentID: sourceDocumentID
        )
        await process(run: run)
        if run.status == .ready {
            try confirmImport(id: run.id)
        }
        return run.id
    }

    private func createRun(
        markdown: String,
        fileName: String,
        sourcePath: String?,
        sourceDocumentID: UUID
    ) throws -> ImportRunRecord {
        let timestamp = now()
        let source = SourceDocumentRecord(
            id: sourceDocumentID,
            fileName: fileName,
            sourcePath: sourcePath,
            contentHash: SHA256.hash(data: Data(markdown.utf8)).map { String(format: "%02x", $0) }.joined(),
            importerVersion: "text-ai-v1",
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
        return run
    }

    private func enqueueProcessing(_ runs: [ImportRunRecord]) {
        guard !runs.isEmpty else { return }
        Task { @MainActor [self] in
            for run in runs {
                await process(run: run)
            }
        }
    }

    private func process(run: ImportRunRecord) async {
        do {
            if run.chunks.contains(where: { $0.status != .completed }) {
                try await decompose(run: run)
            }
            run.status = .ready
            run.errorSummary = nil
            run.updatedAt = now()
            try saveAndExport()
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

    private func decompose(
        run: ImportRunRecord,
        retryFailedChunks: Bool = true
    ) async throws {
        run.status = .decomposing
        run.errorSummary = nil
        run.updatedAt = now()
        try saveAndExport()

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let topicNames = try context.fetch(FetchDescriptor<TopicRecord>())
            .sorted(by: TopicService.libraryOrder)
            .map(\.name)
        let pendingChunks = run.chunks
            .filter { $0.status != .completed }
            .sorted { $0.ordinal < $1.ordinal }
        var workItems: [DecomposeWorkItem] = []
        workItems.reserveCapacity(pendingChunks.count)
        var workItemCountsByChunkID: [UUID: Int] = [:]

        for chunk in pendingChunks {
            guard let data = chunk.contextMarkdown.data(using: .utf8),
                  let envelope = try? decoder.decode(ChunkContextEnvelope.self, from: data) else {
                chunk.status = .failed
                chunk.errorSummary = safeErrorSummary(ImportError.malformedPersistedChunk(chunk.id))
                chunk.updatedAt = now()
                try saveAndExport()
                throw ImportError.malformedPersistedChunk(chunk.id)
            }

            // A failed retry gets a smaller request shape. This is deliberately
            // limited to the retry pass so normal imports keep their larger,
            // more efficient requests and only the provider-sensitive chunks
            // pay the extra round trips.
            let fallbackChunks: [MarkdownImportChunk]
            if !retryFailedChunks,
               chunk.ownedMarkdown.utf16.count > Self.fallbackDecomposeTargetCharacters,
               let split = try? MarkdownChunker(
                    configuration: .init(
                        targetCharacters: Self.fallbackDecomposeTargetCharacters,
                        overlapCharacters: Self.fallbackDecomposeOverlapCharacters
                    )
               ).chunks(markdown: chunk.ownedMarkdown),
               split.count > 1 {
                fallbackChunks = split
            } else {
                fallbackChunks = []
            }

            let fragments: [(markdown: String, contextBefore: String, contextAfter: String, start: Int, end: Int)]
            if fallbackChunks.isEmpty {
                fragments = [(
                    markdown: chunk.ownedMarkdown,
                    contextBefore: envelope.contextBefore,
                    contextAfter: envelope.contextAfter,
                    start: envelope.ownedStartOffset,
                    end: envelope.ownedEndOffset
                )]
            } else {
                fragments = fallbackChunks.map { part in
                    (
                        markdown: part.ownedMarkdown,
                        contextBefore: part.contextBefore,
                        contextAfter: part.contextAfter,
                        start: envelope.ownedStartOffset + part.ownedStartOffset,
                        end: envelope.ownedStartOffset + part.ownedEndOffset
                    )
                }
            }

            for (fragmentIndex, fragment) in fragments.enumerated() {
                workItems.append(
                    DecomposeWorkItem(
                        ordinal: chunk.ordinal,
                        chunkID: chunk.id,
                        request: DecomposeRequest(
                            sourceDocumentID: run.sourceDocument.id,
                            chunkID: chunk.id,
                            markdown: fragment.markdown,
                            contextBefore: fragment.contextBefore,
                            contextAfter: fragment.contextAfter,
                            ownedStartOffset: fragment.start,
                            ownedEndOffset: fragment.end,
                            outputMode: .extraction,
                            availableTopicNames: topicNames
                        ),
                        ownedStartOffset: fragment.start,
                        ownedEndOffset: fragment.end,
                        sourceOrderBase: chunk.ordinal * 1_000_000 + fragmentIndex * 100_000
                    )
                )
            }
            workItemCountsByChunkID[chunk.id] = fragments.count

            // A failed chunk may contain candidates from a previous partially
            // completed retry. They must not be duplicated when this run is
            // continued.
            if chunk.status == .failed {
                for candidate in chunk.candidates {
                    context.delete(candidate)
                }
                chunk.candidates.removeAll()
            }
            chunk.status = .processing
            chunk.errorSummary = nil
            chunk.updatedAt = now()
        }
        try saveAndExport()

        let client = aiClient
        let sourceDocumentID = run.sourceDocument.id
        let chunksByID = Dictionary(uniqueKeysWithValues: pendingChunks.map { ($0.id, $0) })
        var successfulWorkItemCountsByChunkID: [UUID: Int] = [:]
        var failedChunkIDs = Set<UUID>()
        _ = await BoundedAITaskRunner.run(
            inputs: workItems,
            limit: aiConcurrency,
            onResult: { [self] result in
                let item = workItems[result.index]
                guard let chunk = chunksByID[item.chunkID] else { return }

                if let response = result.value {
                    do {
                        let canonicalResponse = try canonicalize(
                            response,
                            for: item.request,
                            failureID: item.chunkID
                        )
                        guard canonicalResponse.candidates.allSatisfy({ draft in
                            !draft.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && !draft.sourceAnchors.isEmpty
                                && draft.sourceAnchors.allSatisfy {
                                    $0.sourceDocumentID == sourceDocumentID
                                        && $0.chunkID == item.chunkID
                                        && $0.startOffset >= item.ownedStartOffset
                                        && $0.endOffset <= item.ownedEndOffset
                                }
                        }) else {
                            throw ImportError.invalidDecomposeResponse(item.chunkID)
                        }
                        for draft in canonicalResponse.candidates {
                            let anchorData = try encoder.encode(draft.sourceAnchors)
                            context.insert(
                                QuestionCandidateRecord(
                                    id: draft.id,
                                    sourceOrder: item.sourceOrderBase + draft.ordinal,
                                    questionText: draft.question,
                                    proposedAnswerText: draft.sourceBackedAnswerMaterial,
                                    sourceAnchor: String(decoding: anchorData, as: UTF8.self),
                                    proposedTopicName: draft.topicName,
                                    createdAt: now(),
                                    importChunk: chunk
                                )
                            )
                        }
                        successfulWorkItemCountsByChunkID[item.chunkID, default: 0] += 1
                        if !failedChunkIDs.contains(item.chunkID),
                           successfulWorkItemCountsByChunkID[item.chunkID] == workItemCountsByChunkID[item.chunkID] {
                            chunk.status = .completed
                            chunk.errorSummary = nil
                        }
                    } catch {
                        failedChunkIDs.insert(item.chunkID)
                        chunk.status = .failed
                        chunk.errorSummary = safeErrorSummary(error)
                    }
                } else {
                    failedChunkIDs.insert(item.chunkID)
                    chunk.status = .failed
                    chunk.errorSummary = result.errorDescription ?? "AI 分解失败"
                }
                chunk.updatedAt = now()
                try? saveAndExport()
            }
        ) { item in
            try await client.decompose(item.request)
        }

        if let firstFailure = pendingChunks.first(where: { $0.status == .failed })?.id {
            if retryFailedChunks {
                // A provider can return HTTP 200 with a response that is
                // structurally decodable but has no source-backed anchor.
                // Retry only those failed chunks once; completed chunks and
                // their candidates remain persisted and are not re-requested.
                for chunk in pendingChunks where chunk.status == .failed {
                    for candidate in chunk.candidates {
                        context.delete(candidate)
                    }
                    chunk.candidates.removeAll()
                    chunk.status = .pending
                    chunk.errorSummary = nil
                    chunk.updatedAt = now()
                }
                try saveAndExport()
                try await decompose(run: run, retryFailedChunks: false)
                return
            }
            throw ImportError.invalidDecomposeResponse(firstFailure)
        }
        guard pendingChunks.allSatisfy({ $0.status == .completed }) else {
            throw ImportError.invalidDecomposeResponse(run.id)
        }
    }

    private struct NormalizedSourceText {
        let characters: [Character]
        let sourceSpans: [(start: String.Index, end: String.Index)]
    }

    /// Rebuilds model-provided anchors from the source quote instead of
    /// trusting offsets or identifiers returned by the provider. Providers
    /// often count UTF-8 bytes, visible characters, or the context envelope
    /// differently from the app's UTF-16 source coordinates.
    private func canonicalize(
        _ response: DecomposeResponse,
        for request: DecomposeRequest,
        failureID: UUID
    ) throws -> DecomposeResponse {
        guard response.completionStatus == .complete else {
#if DEBUG
            print(
                "IF_IMPORT_CANONICALIZE chunk=\(failureID.uuidString) " +
                "reason=completion-\(response.completionStatus.rawValue)"
            )
#endif
            throw ImportError.invalidDecomposeResponse(failureID)
        }

        var candidates: [CandidateDraft] = []
        candidates.reserveCapacity(response.candidates.count)
        var seenIDs = Set<UUID>()
        var lastOrdinal = -1

        for draft in response.candidates {
            guard InterviewQuestionPolicy.accepts(draft.question) else {
#if DEBUG
                print(
                    "IF_IMPORT_CANONICALIZE chunk=\(failureID.uuidString) " +
                    "reason=standalone-concept ordinal=\(draft.ordinal)"
                )
#endif
                continue
            }

            var anchors: [SourceAnchor] = []
            for anchor in draft.sourceAnchors {
                guard let range = sourceRange(
                    for: anchor.exactQuote,
                    in: request.ownedMarkdown
                ) else {
                    continue
                }
                anchors.append(makeCanonicalAnchor(range: range, in: request))
            }

            // If the model returned a malformed or context-only quote, the
            // question itself is the next safest source-backed anchor.
            if anchors.isEmpty,
               let range = sourceRange(for: draft.question, in: request.ownedMarkdown) {
                anchors.append(makeCanonicalAnchor(range: range, in: request))
            }

            guard !anchors.isEmpty else {
#if DEBUG
                print(
                    "IF_IMPORT_CANONICALIZE chunk=\(failureID.uuidString) " +
                    "reason=no-source-anchor ordinal=\(draft.ordinal) " +
                    "providerAnchors=\(draft.sourceAnchors.count)"
                )
#endif
                continue
            }

            let canonicalDraft = CandidateDraft(
                id: draft.id,
                ordinal: draft.ordinal,
                question: draft.question,
                sourceBackedAnswerMaterial: draft.sourceBackedAnswerMaterial,
                sourceAnchors: anchors,
                topicName: draft.topicName
            )

            // Validate candidates independently. One malformed topic, ordinal,
            // duplicate, empty material, or anchor must not poison otherwise
            // source-backed candidates in the same model response.
            guard !seenIDs.contains(canonicalDraft.id),
                  canonicalDraft.ordinal > lastOrdinal else {
#if DEBUG
                print(
                    "IF_IMPORT_CANONICALIZE chunk=\(failureID.uuidString) " +
                    "reason=invalid-candidate-order ordinal=\(canonicalDraft.ordinal)"
                )
#endif
                continue
            }
            do {
                try AIResponseValidator.validate(
                    DecomposeResponse(
                        candidates: [canonicalDraft],
                        completionStatus: response.completionStatus
                    ),
                    for: request
                )
            } catch {
#if DEBUG
                print(
                    "IF_IMPORT_CANONICALIZE chunk=\(failureID.uuidString) " +
                    "reason=invalid-candidate-\(String(describing: error)) ordinal=\(canonicalDraft.ordinal)"
                )
#endif
                continue
            }
            candidates.append(canonicalDraft)
            seenIDs.insert(canonicalDraft.id)
            lastOrdinal = canonicalDraft.ordinal
        }

        if !response.candidates.isEmpty, candidates.isEmpty {
            throw ImportError.invalidDecomposeResponse(failureID)
        }

        let canonicalResponse = DecomposeResponse(
            candidates: candidates,
            completionStatus: response.completionStatus
        )
        do {
            try AIResponseValidator.validate(canonicalResponse, for: request)
        } catch {
#if DEBUG
            print(
                "IF_IMPORT_CANONICALIZE chunk=\(failureID.uuidString) " +
                "reason=validation-\(String(describing: error))"
            )
#endif
            throw ImportError.invalidDecomposeResponse(failureID)
        }
        return canonicalResponse
    }

    private func makeCanonicalAnchor(
        range: Range<String.Index>,
        in request: DecomposeRequest
    ) -> SourceAnchor {
        let exactQuote = String(request.ownedMarkdown[range])
        let localStart = String(request.ownedMarkdown[..<range.lowerBound]).utf16.count
        let startOffset = request.ownedStartOffset + localStart
        let endOffset = startOffset + exactQuote.utf16.count
        return SourceAnchor(
            sourceDocumentID: request.sourceDocumentID,
            chunkID: request.chunkID,
            startOffset: startOffset,
            endOffset: endOffset,
            exactQuote: exactQuote
        )
    }

    private func sourceRange(for quote: String, in source: String) -> Range<String.Index>? {
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let exactRange = source.range(of: quote) {
            return exactRange
        }

        let normalizedSource = normalizedSourceText(source)
        let normalizedQuote = normalizedSourceText(quote).characters
        guard !normalizedQuote.isEmpty,
              normalizedQuote.count <= normalizedSource.characters.count else {
            return nil
        }

        let lastStart = normalizedSource.characters.count - normalizedQuote.count
        for start in 0...lastStart {
            let end = start + normalizedQuote.count
            guard Array(normalizedSource.characters[start..<end]) == normalizedQuote else {
                continue
            }
            let lowerBound = normalizedSource.sourceSpans[start].start
            let upperBound = normalizedSource.sourceSpans[end - 1].end
            return lowerBound..<upperBound
        }
        return nil
    }

    private func normalizedSourceText(_ text: String) -> NormalizedSourceText {
        var characters: [Character] = []
        var sourceSpans: [(start: String.Index, end: String.Index)] = []
        var index = text.startIndex

        while index < text.endIndex {
            let end = text.index(after: index)
            let character = text[index]
            if character.isWhitespace {
                if characters.last != " " {
                    characters.append(" ")
                    sourceSpans.append((start: index, end: end))
                } else {
                    sourceSpans[sourceSpans.count - 1].end = end
                }
            } else {
                let mappedCharacter = normalizedAnchorCharacter(character)
                let folded = String(mappedCharacter)
                    .precomposedStringWithCanonicalMapping
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                for foldedCharacter in folded {
                    characters.append(foldedCharacter)
                    sourceSpans.append((start: index, end: end))
                }
            }
            index = end
        }

        var first = 0
        while first < characters.count, characters[first] == " " {
            first += 1
        }
        var last = characters.count
        while last > first, characters[last - 1] == " " {
            last -= 1
        }
        return NormalizedSourceText(
            characters: Array(characters[first..<last]),
            sourceSpans: Array(sourceSpans[first..<last])
        )
    }

    private func normalizedAnchorCharacter(_ character: Character) -> Character {
        switch character {
        case "，": ","
        case "。": "."
        case "！": "!"
        case "？": "?"
        case "：": ":"
        case "；": ";"
        case "（": "("
        case "）": ")"
        case "【": "["
        case "】": "]"
        case "“", "”": "\""
        case "‘", "’": "'"
        default: character
        }
    }

    private func promoteDecomposedCandidates(run: ImportRunRecord) throws {
        let candidates = run.chunks
            .flatMap(\.candidates)
            .sorted { $0.sourceOrder < $1.sourceOrder }
        guard !candidates.isEmpty,
              run.chunks.allSatisfy({ $0.status == .completed }) else {
            throw ImportError.invalidDecomposeResponse(run.id)
        }

        for candidate in candidates {
            candidate.status = .refined
        }
        run.updatedAt = now()
        try saveAndExport()
    }

    private func createRefinementBatches(run: ImportRunRecord) throws {
        let candidates = run.chunks
            .flatMap(\.candidates)
            .sorted { $0.sourceOrder < $1.sourceOrder }
        let timestamp = now()
        for (ordinal, start) in stride(from: 0, to: candidates.count, by: refinementBatchSize).enumerated() {
            let end = min(start + refinementBatchSize, candidates.count)
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
        let pendingBatches = run.refinementBatches
            .filter { $0.status != .completed }
            .sorted { $0.ordinal < $1.ordinal }
        var workItems: [RefineWorkItem] = []
        var recordsByBatchID: [UUID: [QuestionCandidateRecord]] = [:]
        workItems.reserveCapacity(pendingBatches.count)

        for batch in pendingBatches {
            let records = batch.candidates.sorted { $0.sourceOrder < $1.sourceOrder }
            guard records.count <= 50 else {
                batch.status = .failed
                batch.errorSummary = safeErrorSummary(ImportError.invalidRefineResponse(batch.id))
                batch.updatedAt = now()
                try saveAndExport()
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
                    sourceAnchors: anchors,
                    topicName: record.proposedTopicName
                )
            }
            workItems.append(
                RefineWorkItem(
                    ordinal: batch.ordinal,
                    batchID: batch.id,
                    request: RefineRequest(
                        sourceDocumentID: run.sourceDocument.id,
                        batchID: batch.id,
                        candidates: drafts,
                        availableTopicNames: topicNames
                    )
                )
            )
            recordsByBatchID[batch.id] = records
            batch.status = .processing
            batch.errorSummary = nil
            batch.updatedAt = now()
        }
        try saveAndExport()

        let client = aiClient
        let results = await BoundedAITaskRunner.run(inputs: workItems, limit: aiConcurrency) { item in
            let response = try await client.refine(item.request)
            try AIResponseValidator.validate(
                response,
                allowedTopics: Set(item.request.availableTopicNames)
            )
            guard response.completionStatus == .complete else {
                throw ImportError.invalidRefineResponse(item.batchID)
            }
            return response
        }

        let batchesByID = Dictionary(uniqueKeysWithValues: pendingBatches.map { ($0.id, $0) })
        var firstFailureError: ImportError?
        for result in results {
            let item = workItems[result.index]
            guard let batch = batchesByID[item.batchID],
                  let records = recordsByBatchID[item.batchID] else { continue }
            if let response = result.value {
                let snapshots = Dictionary(uniqueKeysWithValues: records.map {
                    ($0.id, CandidateMutationSnapshot(
                        questionText: $0.questionText,
                        proposedAnswerText: $0.proposedAnswerText,
                        proposedTopicName: $0.proposedTopicName,
                        sourceAnchor: $0.sourceAnchor,
                        status: $0.status
                    ))
                })
                do {
                    try stage(
                        response: response,
                        records: records,
                        batch: batch,
                        decoder: decoder,
                        encoder: encoder
                    )
                    batch.status = .completed
                    batch.errorSummary = nil
                } catch {
                    for record in records {
                        guard let snapshot = snapshots[record.id] else { continue }
                        record.questionText = snapshot.questionText
                        record.proposedAnswerText = snapshot.proposedAnswerText
                        record.proposedTopicName = snapshot.proposedTopicName
                        record.sourceAnchor = snapshot.sourceAnchor
                        record.status = snapshot.status
                    }
                    if firstFailureError == nil {
                        firstFailureError = (error as? ImportError)
                            ?? .invalidRefineResponse(batch.id)
                    }
                    batch.status = .failed
                    batch.errorSummary = safeErrorSummary(error)
                }
            } else {
                if firstFailureError == nil {
                    firstFailureError = .invalidRefineResponse(item.batchID)
                }
                batch.status = .failed
                batch.errorSummary = result.errorDescription ?? "AI 润色去重失败"
            }
            batch.updatedAt = now()
            try saveAndExport()
        }
        if let firstFailureError {
            throw firstFailureError
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
        guard run.chunks.allSatisfy({ $0.status == .completed }) else {
            throw ImportError.invalidRefineResponse(run.id)
        }

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        guard let others = topics.first(where: { $0.systemKind == .others }) else {
            throw ImportError.missingOthersTopic
        }
        // Look topics up with the same whitespace-insensitive key used by
        // AIResponseValidator so a model label such as "system design" resolves
        // to a stored topic "system design" that contains invisible spacing
        // (U+2006) instead of failing the activation contract.
        var topicByNormalizedKey: [String: TopicRecord] = [:]
        for topic in topics {
            let key = TopicNameNormalization.key(topic.name)
            if topicByNormalizedKey[key] == nil {
                topicByNormalizedKey[key] = topic
            }
        }
        let importableCandidates = run.chunks
            .flatMap(\.candidates)
            .filter { $0.status.isActivationEligible }
            .sorted { $0.sourceOrder < $1.sourceOrder }

        var activationPlans: [ActivationPlan] = []
        activationPlans.reserveCapacity(importableCandidates.count)
        for candidate in importableCandidates {
            activationPlans.append(ActivationPlan(candidate: candidate, keyPointsJSON: "[]"))
        }

        run.status = .activating
        run.updatedAt = now()
        try saveAndExport()

        let timestamp = now()
        var nextQuestionNumber = try numberingService.nextNumber(context: context)
        for plan in activationPlans {
            let candidate = plan.candidate
            let topic: TopicRecord
            let normalizedTopicName = InterviewQuestionPolicy.normalizedTopicName(
                proposedTopicName: candidate.proposedTopicName,
                question: candidate.questionText,
                material: candidate.proposedAnswerText,
                othersName: others.name,
                availableTopicNames: topics.map(\.name)
            )
            if let proposedTopicName = normalizedTopicName {
                guard let resolvedTopic = topicByNormalizedKey[
                    TopicNameNormalization.key(proposedTopicName)
                ] else {
                    // Never silently convert a non-empty model label into
                    // Others. A label mismatch means the generation contract
                    // was violated and the import must remain reviewable.
                    throw ImportError.invalidRefineResponse(run.id)
                }
                topic = resolvedTopic
            } else {
                // Candidates persisted by pre-v4 extraction did not contain a
                // topic. Keep those already-created review runs importable;
                // new generation requests are validated as topic-required.
                topic = others
            }
            let card = QuestionCardRecord(
                questionNumber: nextQuestionNumber,
                questionText: candidate.questionText,
                sourceAnchor: candidate.sourceAnchor,
                createdAt: timestamp,
                updatedAt: timestamp,
                activatedAt: timestamp,
                topic: topic,
                sourceDocument: run.sourceDocument
            )
            context.insert(card)
            nextQuestionNumber += 1
            candidate.status = .extracted
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

    private func decodeText(_ data: Data, fileName: String) throws -> String {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            .windowsCP1252,
            .isoLatin1,
            .macOSRoman
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw ImportError.invalidTextEncoding(fileName)
    }

    private func safeErrorSummary(_ error: Error) -> String {
        if let error = error as? AIError {
            return String(describing: error)
        }
        if let error = error as? ImportError {
            return String(describing: error)
        }
        return String(describing: type(of: error))
    }

    private static func defaultImportsDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
    }
}
