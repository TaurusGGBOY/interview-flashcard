import Foundation
import SwiftData
import XCTest

final class ImportCoordinatorTests: XCTestCase {
    @MainActor
    func testRefinementBatchesNeverMixDocumentsAndMaxAtFifty() {
        let batches = ImportCoordinator.makeBatchPlan(candidateCounts: [101, 12])
        XCTAssertEqual(batches.map(\.candidateCount), [50, 50, 1, 12])
        XCTAssertEqual(batches.map(\.sourceIndex), [0, 0, 0, 1])
        XCTAssertTrue(batches.allSatisfy(\.containsSingleSourceDocument))
    }

    @MainActor
    func testSampleImportActivatesCardsWithoutGeneratingReferenceAnswers() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())

        let runID = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")

        let runs = try context.fetch(FetchDescriptor<ImportRunRecord>())
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let orderedCandidates = try XCTUnwrap(runs.first(where: { $0.id == runID }))
            .chunks
            .flatMap(\.candidates)
            .sorted { $0.sourceOrder < $1.sourceOrder }
        let cardsByAnchor = Dictionary(uniqueKeysWithValues: cards.map { ($0.sourceAnchor, $0) })
        XCTAssertEqual(runs.first(where: { $0.id == runID })?.status, .active)
        XCTAssertEqual(cards.count, 3)
        XCTAssertTrue(cards.allSatisfy { $0.topic.systemKind == .others })
        XCTAssertTrue(cards.allSatisfy { $0.referenceAnswers.isEmpty && !$0.sourceAnchor.isEmpty })
        XCTAssertEqual(
            orderedCandidates.compactMap { cardsByAnchor[$0.sourceAnchor]?.questionNumber },
            [1, 2, 3]
        )
    }

    @MainActor
    func testQuestionGenerationPersistsExactExistingTopicFromDecomposeJSON() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        _ = try TopicService().create(name: "K8S", context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())

        let runID = try await coordinator.start(
            markdown: "## Q01 Kubernetes Pod 调度\n\nKubernetes（K8S）通过调度器选择节点。",
            fileName: "kubernetes.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let candidates = run.chunks.flatMap(\.candidates)
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        XCTAssertEqual(candidates.map(\.proposedTopicName), ["K8S"])
        XCTAssertEqual(cards.map(\.topic.name), ["K8S"])
        XCTAssertTrue(cards.allSatisfy { $0.topic.systemKind != .others })
    }

    @MainActor
    func testImportResolvesTopicStoredWithInvisibleSpacing() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        // Legacy topic persisted with U+2006 before the hygiene pass; the
        // coordinator must still resolve a normal-spaced model label to it.
        let pollutedTopic = TopicRecord(
            name: "system\u{2006}design",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now
        )
        context.insert(pollutedTopic)
        try context.save()

        // The stub echoes the whitelist topic name but with normal spacing,
        // exactly the failure mode that made run-level imports fail.
        let coordinator = makeCoordinator(
            context: context,
            client: TopicCleaningStubClient()
        )

        let runID = try await coordinator.start(
            markdown: "## Q01 系统设计\n\n设计一个短链接系统。",
            fileName: "system-design.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.topic.id, pollutedTopic.id)
        XCTAssertEqual(cards.first?.topic.name, "system\u{2006}design")
    }

    @MainActor
    func testTextFileImportAcceptsUTF16TXTAndPreservesSourceDocument() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterviewFlashcardTextImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("interview-notes.txt")
        let text = """
        ## Q01

        这是一份普通 TXT 文本，也应当使用真实导入管线处理。
        """
        try XCTUnwrap(text.data(using: .utf16)).write(to: fileURL)

        let runIDs = try await coordinator.start(urls: [fileURL])

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runIDs[0] })
        )
        XCTAssertNotEqual(run.status, .active)
        XCTAssertEqual(run.sourceDocument.fileName, "interview-notes.txt")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)

        let readyRun = try await waitForRun(
            id: runIDs[0],
            context: context,
            status: .ready
        )
        XCTAssertTrue(readyRun.chunks.flatMap(\.candidates).contains { $0.questionText == "Q01 的核心问题是什么？" })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)

        try coordinator.confirmImport(id: runIDs[0])
        let importedRun = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runIDs[0] })
        )
        XCTAssertEqual(importedRun.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 1)
    }

    @MainActor
    func testFileImportConfirmationPublishesCardsAndCompletesAnswerScoring() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterviewFlashcardImportScoreFlow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("score-flow.md")
        try XCTUnwrap(Self.sampleMarkdown.data(using: .utf8)).write(to: fileURL)

        let importer = makeCoordinator(context: context, client: StubAIClient())
        let runIDs = try await importer.start(urls: [fileURL])
        let runID = try XCTUnwrap(runIDs.first)
        let readyRun = try await waitForRun(id: runID, context: context, status: .ready)

        let pendingCandidates = readyRun.chunks
            .flatMap(\.candidates)
            .filter { $0.status == .pending }
        XCTAssertEqual(pendingCandidates.count, 3)
        XCTAssertTrue(pendingCandidates.allSatisfy(\.status.isActivationEligible))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)

        try importer.confirmImport(id: runID)

        let activeRun = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        XCTAssertEqual(activeRun.status, .active)
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(LibrarySearch.results(from: cards, query: "类加载").count, 1)
        XCTAssertTrue(cards.allSatisfy { $0.sourceDocument.id == activeRun.sourceDocument.id })

        let card = try XCTUnwrap(cards.first)
        let attempt = try AnswerSubmissionService(now: { Fixtures.now }).submitText(
            questionID: card.id,
            rawText: "类加载包括加载、验证、准备、解析和初始化。",
            context: context
        )
        let evaluation = try await AnswerProcessingService(
            aiClient: RetryingAIClient(base: StubAIClient(), retryDelayNanoseconds: 0),
            now: { Fixtures.now }
        ).processStaged(attemptID: attempt.id, context: context)

        XCTAssertEqual(evaluation.status, .completed)
        XCTAssertEqual(evaluation.totalScore, 75)
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertFalse(attempt.referenceAnswerTextSnapshot.isEmpty)
        XCTAssertEqual(attempt.evaluations.count, 1)
    }

    @MainActor
    func testFileImportReturnsBeforeBackgroundAnalysisAndRequiresExplicitConfirmation() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterviewFlashcardBackgroundImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("background.md")
        try XCTUnwrap(Self.sampleMarkdown.data(using: .utf8)).write(to: fileURL)

        let coordinator = makeCoordinator(
            context: context,
            client: ImportConcurrencyAIClient(delayNanoseconds: 200_000_000),
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 200_000, overlapCharacters: 120)),
            singlePassLLMImport: true
        )
        let runIDs = try await coordinator.start(urls: [fileURL])

        let runImmediatelyAfterEnqueue = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runIDs[0] })
        )
        XCTAssertNotEqual(runImmediatelyAfterEnqueue.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)

        _ = try await waitForRun(id: runIDs[0], context: context, status: .ready)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)

        try coordinator.confirmImport(id: runIDs[0])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runIDs[0] })?.status,
            .active
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 3)

        try coordinator.confirmImport(id: runIDs[0])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 3)
    }

    @MainActor
    func testLaunchRecoveryLeavesReadyImportForExplicitConfirmation() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)

        let source = SourceDocumentRecord(
            fileName: "ready.md",
            contentHash: "ready-hash",
            importerVersion: "text-ai-v1",
            importedAt: Fixtures.now
        )
        let run = ImportRunRecord(
            status: .ready,
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now,
            sourceDocument: source
        )
        context.insert(source)
        context.insert(run)
        try context.save()

        let importer = makeCoordinator(context: context, client: StubAIClient())
        await LaunchRecoveryCoordinator(importer: importer).resume(context: context)

        XCTAssertEqual(run.status, .ready)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)
    }

    @MainActor
    func testQuestionLikeHeadingsStillUseGenericAIImportPath() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let client = ImportConcurrencyAIClient(delayNanoseconds: 0)
        let coordinator = makeCoordinator(
            context: context,
            client: client,
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 200_000, overlapCharacters: 120))
        )

        let runID = try await coordinator.start(
            markdown: """
            # Kubernetes 面试记录

            #### Q-001 这是一道看起来像编号题目的标题？

            但导入器仍然必须交给通用 AI 链路判断题目边界、答案和证据。

            #### Q-002 另一道看起来像编号题目的标题？

            原文可能是自然段、列表或混合格式，不能因为标题形状而绕过模型。
            """,
            fileName: "question-like-headings.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let decomposeChunkCount = await client.decomposeChunkIDs().count
        let refineBatchCount = await client.refineBatchIDs().count

        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(decomposeChunkCount, run.chunks.count)
        XCTAssertEqual(refineBatchCount, 0)
        XCTAssertTrue(run.chunks.flatMap(\.candidates).allSatisfy { $0.status == .extracted })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 0)
    }

    @MainActor
    func testRepeatedSameMarkdownCreatesIndependentSourcesAndCards() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())

        _ = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")
        _ = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocumentRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 6)
    }

    @MainActor
    func testLongImportSkipsReferenceAnswerRefinementBatches() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())
        let markdown = (1...52).map { index in
            let number = String(format: "%02d", index)
            return "## Q\(number) 唯一问题\n\n\(Fixtures.indentedSeniorReferenceAnswer)\n"
        }.joined(separator: "\n")

        _ = try await coordinator.start(markdown: markdown, fileName: "long-interview.md")

        let run = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportRunRecord>()).first)
        XCTAssertTrue(run.refinementBatches.isEmpty)
        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 52)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 0)
    }

    @MainActor
    func testImportUsesBoundedConcurrencyAcrossIndependentChunks() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let client = ImportConcurrencyAIClient(delayNanoseconds: 20_000_000)
        let coordinator = makeCoordinator(
            context: context,
            client: client,
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 500, overlapCharacters: 80))
        )

        let runID = try await coordinator.start(
            markdown: Self.generatedMarkdown(questionCount: 18, body: String(repeating: "系统需要处理失败、超时和资源受限等边界。", count: 8)),
            fileName: "concurrent-chunks.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let candidates = run.chunks.flatMap(\.candidates)
        let decomposeChunkIDCount = await client.decomposeChunkIDs().count
        let maximumActive = await client.maximumActiveCalls()
        XCTAssertGreaterThanOrEqual(run.chunks.count, 6)
        XCTAssertEqual(decomposeChunkIDCount, run.chunks.count)
        XCTAssertGreaterThanOrEqual(maximumActive, 2)
        XCTAssertLessThanOrEqual(maximumActive, 4)
        XCTAssertEqual(run.status, .active)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.status == .extracted })
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<QuestionCardRecord>()),
            candidates.count
        )
    }

    @MainActor
    func testLargeImportDoesNotRunReferenceAnswerRefinement() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let client = ImportConcurrencyAIClient(delayNanoseconds: 20_000_000)
        let coordinator = makeCoordinator(
            context: context,
            client: client,
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 200_000, overlapCharacters: 120))
        )

        let runID = try await coordinator.start(
            markdown: Self.generatedMarkdown(questionCount: 151, body: "解释机制、失败路径和工程取舍。"),
            fileName: "concurrent-refinement.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let candidates = run.chunks
            .flatMap(\.candidates)
            .sorted { $0.sourceOrder < $1.sourceOrder }
        let refineBatchIDCount = await client.refineBatchIDs().count
        let maximumActive = await client.maximumActiveCalls()

        XCTAssertTrue(run.refinementBatches.isEmpty)
        XCTAssertEqual(refineBatchIDCount, 0)
        XCTAssertLessThanOrEqual(maximumActive, 4)
        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(candidates.count, 151)
        XCTAssertEqual(candidates.map(\.sourceOrder), Array(0..<151))
        XCTAssertTrue(candidates.allSatisfy { $0.status == .extracted })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 151)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 0)
    }

    @MainActor
    func testRefinementFailureModeDoesNotAffectQuestionExtraction() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(
            context: context,
            client: StubAIClient(mode: .refineAlwaysFail)
        )

        let runID = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")
        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )

        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<QuestionCardRecord>()),
            3
        )
        XCTAssertTrue(run.chunks.flatMap(\.candidates).allSatisfy { $0.status == .extracted })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 0)
    }

    @MainActor
    func testTransientFailureIsRetriedOnce() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(
            context: context,
            client: StubAIClient(mode: .transientOnce)
        )

        _ = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")

        XCTAssertEqual(try context.fetch(FetchDescriptor<ImportRunRecord>()).first?.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 3)
    }

    @MainActor
    func testInvalidDecomposeResponseIsRetriedBeforeRunFails() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let client = InvalidOnceDecomposeAIClient()
        let coordinator = makeCoordinator(context: context, client: client)

        let runID = try await coordinator.start(
            markdown: Self.sampleMarkdown,
            fileName: "invalid-once.md"
        )
        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )

        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 3)
        let callCount = await client.decomposeCallCount()
        XCTAssertEqual(callCount, run.chunks.count + 1)
    }

    @MainActor
    func testInvalidReferenceAnswerRefinementClientIsUnusedDuringImport() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(
            context: context,
            client: InvalidReferenceAnswerAIClient(invalidCardIndex: 2)
        )

        let runID = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "invalid-answer.md")

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        XCTAssertEqual(run.status, .active)
        XCTAssertTrue(run.errorSummary == nil)
        XCTAssertTrue(run.chunks.flatMap(\.candidates).allSatisfy { $0.status == .extracted })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 0)
    }

    @MainActor
    func testActivationAcceptsExtractedCandidatesWithoutReferenceAnswers() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())
        let runID = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "activation-bypass.md")
        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )

        XCTAssertEqual(run.status, .active)
        XCTAssertTrue(run.chunks.flatMap(\.candidates).allSatisfy { $0.status == .extracted })
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        XCTAssertEqual(cards.count, 3)
        XCTAssertTrue(cards.allSatisfy { $0.referenceAnswers.isEmpty })
    }

    @MainActor
    func testStandaloneConceptsAreNotCardsAndKubernetesQuestionsDoNotFallIntoOthers() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        _ = try TopicService().create(name: "Kubernetes", context: context, now: Fixtures.now)

        let coordinator = makeCoordinator(
            context: context,
            client: StandaloneConceptAIClient()
        )
        let runID = try await coordinator.start(
            markdown: "## Pod\n\nKubernetes Pod 的基本说明。\n\n## Kubernetes Pod 调度如何工作？\n\n调度器根据约束选择节点。",
            fileName: "kubernetes.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())

        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.questionText, "Kubernetes Pod 调度如何工作？")
        XCTAssertEqual(cards.first?.topic.name, "Kubernetes")
    }

    @MainActor
    func testMalformedCandidateDoesNotDiscardOtherValidCandidatesInSameChunk() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(
            context: context,
            client: MixedAnchorAIClient()
        )

        let runID = try await coordinator.start(
            markdown: "## Kubernetes Pod 调度\n\n调度器根据约束选择节点。",
            fileName: "mixed-anchor.md"
        )

        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())

        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.questionText, "Kubernetes Pod 调度如何工作？")
    }

    @MainActor
    func testTruncatedChunkIsRetriedWithSmallerRequests() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let client = TruncatingDecomposeAIClient(threshold: 5_000)
        let coordinator = makeCoordinator(
            context: context,
            client: client,
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 10_000, overlapCharacters: 200)),
            singlePassLLMImport: true
        )
        let body = (1...180).map { "第\($0) 行：系统需要处理失败、超时和资源受限等边界，并记录可验证的原文证据。" }
            .joined(separator: "\n")

        let runID = try await coordinator.start(
            markdown: "## Kubernetes Pod 调度\n\n\(body)",
            fileName: "truncated-retry.md"
        )
        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let requestSizes = await client.requestSizes()

        XCTAssertEqual(run.status, .active)
        XCTAssertFalse(run.chunks.flatMap(\.candidates).isEmpty)
        XCTAssertTrue(requestSizes.contains(where: { $0 > 5_000 }))
        XCTAssertTrue(requestSizes.contains(where: { $0 <= 4_000 }))
    }

    @MainActor
    private func makeCoordinator(
        context: ModelContext,
        client: any AIClient,
        chunker: MarkdownChunker? = nil,
        singlePassLLMImport: Bool = false
    ) -> ImportCoordinator {
        ImportCoordinator(
            context: context,
            aiClient: client,
            chunker: chunker ?? MarkdownChunker(configuration: .init(targetCharacters: 1_200, overlapCharacters: 180)),
            diagnostics: .init(isEnabled: false),
            importsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("InterviewFlashcardImportTests", isDirectory: true),
            retryDelayNanoseconds: 0,
            singlePassLLMImport: singlePassLLMImport,
            numberingService: QuestionNumberingService(
                defaults: UserDefaults(suiteName: "ImportCoordinatorTests.\(UUID().uuidString)")!
            ),
            now: { Fixtures.now }
        )
    }

    @MainActor
    private func waitForRun(
        id: UUID,
        context: ModelContext,
        status expectedStatus: ImportRunStatus,
        timeout: TimeInterval = 10
    ) async throws -> ImportRunRecord {
        let deadline = Date().addingTimeInterval(timeout)
        let descriptor = FetchDescriptor<ImportRunRecord>(
            predicate: #Predicate { run in
                run.id == id
            }
        )
        while Date() < deadline {
            if let run = try context.fetch(descriptor).first, run.status == expectedStatus {
                return run
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let run = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTFail("Import run did not reach \(expectedStatus); actual status: \(run.status)")
        return run
    }

    private static func generatedMarkdown(questionCount: Int, body: String) -> String {
        (1...questionCount).map { index in
            let number = String(format: "%03d", index)
            return "## Q\(number)\n\n\(body)\n"
        }.joined(separator: "\n")
    }

    private static let sampleMarkdown = """
    # 面试题样本

    ## JVM 类加载阶段

    \(Fixtures.indentedSeniorReferenceAnswer)

    ## HashMap 扩容

    \(Fixtures.indentedSeniorReferenceAnswer)

    ```swift
    let text = "## 这不是题目"
    print(text)
    ```

    ## CAP 取舍

    \(Fixtures.indentedSeniorReferenceAnswer)
    """
}

private actor ImportConcurrencyAIClient: AIClient {
    private let base = StubAIClient()
    private let delayNanoseconds: UInt64
    private var activeCalls = 0
    private var maximumActive = 0
    private var chunkIDs: [UUID] = []
    private var batchIDs: [UUID] = []
    private var candidateOrdinals: [[Int]] = []

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func maximumActiveCalls() -> Int {
        maximumActive
    }

    func decomposeChunkIDs() -> [UUID] {
        chunkIDs
    }

    func refineBatchIDs() -> [UUID] {
        batchIDs
    }

    func refineCandidateOrdinals() -> [[Int]] {
        candidateOrdinals
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        beginCall()
        defer { endCall() }
        chunkIDs.append(request.chunkID)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await base.decompose(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        beginCall()
        defer { endCall() }
        batchIDs.append(request.batchID)
        candidateOrdinals.append(request.candidates.map(\.ordinal))
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    private func beginCall() {
        activeCalls += 1
        maximumActive = max(maximumActive, activeCalls)
    }

    private func endCall() {
        activeCalls -= 1
    }
}

private actor InvalidReferenceAnswerAIClient: AIClient {
    private let base = StubAIClient()
    private let invalidCardIndex: Int

    init(invalidCardIndex: Int) {
        self.invalidCardIndex = invalidCardIndex
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await base.decompose(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        let response = try await base.refine(request)
        let cards = response.cards.enumerated().map { index, card in
            guard index == invalidCardIndex else { return card }
            return RefinedCardDraft(
                id: card.id,
                mergedCandidateIDs: card.mergedCandidateIDs,
                question: card.question,
                fullScoreAnswer: "只有泛泛定义。",
                topicName: card.topicName,
                sourceAnchors: card.sourceAnchors
            )
        }
        return RefineResponse(cards: cards, completionStatus: response.completionStatus)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }
}

private actor InvalidOnceDecomposeAIClient: AIClient {
    private let base = StubAIClient()
    private var shouldReturnInvalidResponse = true
    private(set) var calls = 0

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        calls += 1
        let response = try await base.decompose(request)
        guard shouldReturnInvalidResponse else { return response }
        shouldReturnInvalidResponse = false
        return DecomposeResponse(
            candidates: response.candidates,
            completionStatus: .truncated
        )
    }

    func decomposeCallCount() -> Int { calls }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try await base.referenceAnswer(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        try await base.score(request)
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        try await base.evaluationFeedback(request)
    }
}

private actor StandaloneConceptAIClient: AIClient {
    private let base = StubAIClient()

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        let anchor = SourceAnchor(
            sourceDocumentID: request.sourceDocumentID,
            chunkID: request.chunkID,
            startOffset: request.ownedStartOffset,
            endOffset: request.ownedEndOffset,
            exactQuote: request.ownedMarkdown
        )
        return DecomposeResponse(
            candidates: [
                CandidateDraft(
                    id: UUID(uuidString: "77000000-0000-0000-0000-000000000001")!,
                    ordinal: 0,
                    question: "Pod",
                    sourceBackedAnswerMaterial: "Kubernetes Pod 的基本说明。",
                    sourceAnchors: [anchor],
                    topicName: "Others"
                ),
                CandidateDraft(
                    id: UUID(uuidString: "77000000-0000-0000-0000-000000000002")!,
                    ordinal: 1,
                    question: "Kubernetes Pod 调度如何工作？",
                    sourceBackedAnswerMaterial: "调度器根据约束选择节点。",
                    sourceAnchors: [anchor],
                    topicName: "Others"
                )
            ],
            completionStatus: .complete
        )
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }
}

private actor MixedAnchorAIClient: AIClient {
    private let base = StubAIClient()

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        let validAnchor = SourceAnchor(
            sourceDocumentID: request.sourceDocumentID,
            chunkID: request.chunkID,
            startOffset: request.ownedStartOffset,
            endOffset: request.ownedStartOffset + "## Kubernetes Pod 调度".utf16.count,
            exactQuote: "## Kubernetes Pod 调度"
        )
        let invalidAnchor = SourceAnchor(
            sourceDocumentID: request.sourceDocumentID,
            chunkID: request.chunkID,
            startOffset: request.ownedStartOffset,
            endOffset: request.ownedEndOffset,
            exactQuote: "这段内容并不存在于原文"
        )
        return DecomposeResponse(
            candidates: [
                CandidateDraft(
                    id: UUID(uuidString: "88000000-0000-0000-0000-000000000001")!,
                    ordinal: 0,
                    question: "Kubernetes Pod 调度如何工作？",
                    sourceBackedAnswerMaterial: "调度器根据约束选择节点。",
                    sourceAnchors: [validAnchor],
                    topicName: "Others"
                ),
                CandidateDraft(
                    id: UUID(uuidString: "88000000-0000-0000-0000-000000000002")!,
                    ordinal: 1,
                    question: "Kubernetes Pod 为什么会被调度到某个节点？",
                    sourceBackedAnswerMaterial: "模型返回的候选没有可靠原文证据。",
                    sourceAnchors: [invalidAnchor],
                    topicName: "Others"
                )
            ],
            completionStatus: .complete
        )
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }
}

private actor TruncatingDecomposeAIClient: AIClient {
    private let base = StubAIClient()
    private let threshold: Int
    private var sizes: [Int] = []

    init(threshold: Int) {
        self.threshold = threshold
    }

    func requestSizes() -> [Int] { sizes }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        sizes.append(request.ownedMarkdown.utf16.count)
        if request.ownedMarkdown.utf16.count > threshold {
            throw AIError.truncatedResponse
        }
        return try await base.decompose(request)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try await base.referenceAnswer(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        try await base.score(request)
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        try await base.evaluationFeedback(request)
    }
}

/// Simulates a provider that echoes whitelist topic names with normal spacing
/// while the store still contains invisible U+2006 variants (the bug that made
/// chunk-level decompose validation fail for every candidate).
private actor TopicCleaningStubClient: AIClient {
    private let base = StubAIClient()

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        let response = try await base.decompose(request)
        return DecomposeResponse(
            candidates: response.candidates.map { candidate in
                CandidateDraft(
                    id: candidate.id,
                    ordinal: candidate.ordinal,
                    question: candidate.question,
                    sourceBackedAnswerMaterial: candidate.sourceBackedAnswerMaterial,
                    sourceAnchors: candidate.sourceAnchors,
                    topicName: candidate.topicName.map(TopicNameNormalization.cleanedForStorage)
                )
            },
            completionStatus: response.completionStatus
        )
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try await base.referenceAnswer(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await base.refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await base.reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await base.polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await base.evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        try await base.score(request)
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        try await base.evaluationFeedback(request)
    }
}
