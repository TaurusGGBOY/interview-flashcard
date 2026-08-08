import Foundation
import SwiftData
import XCTest
@testable import InterviewFlashcard

final class ImportCoordinatorTests: XCTestCase {
    func testRefinementBatchesNeverMixDocumentsAndMaxAtFifty() {
        let batches = ImportCoordinator.makeBatchPlan(candidateCounts: [101, 12])
        XCTAssertEqual(batches.map(\.candidateCount), [50, 50, 1, 12])
        XCTAssertEqual(batches.map(\.sourceIndex), [0, 0, 0, 1])
        XCTAssertTrue(batches.allSatisfy(\.containsSingleSourceDocument))
    }

    @MainActor
    func testSampleImportActivatesThreeCardsOnlyAfterRefinement() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let coordinator = makeCoordinator(context: context, client: StubAIClient())

        let runID = try await coordinator.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")

        let runs = try context.fetch(FetchDescriptor<ImportRunRecord>())
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        XCTAssertEqual(runs.first(where: { $0.id == runID })?.status, .active)
        XCTAssertEqual(cards.count, 3)
        XCTAssertTrue(cards.allSatisfy { $0.topic.systemKind == .others })
        XCTAssertTrue(cards.allSatisfy { !$0.referenceAnswers.isEmpty && !$0.sourceAnchor.isEmpty })
        for card in cards {
            let reference = try XCTUnwrap(card.referenceAnswers.first)
            let data = try XCTUnwrap(reference.keyPointsJSON.data(using: .utf8))
            let keyPoints = try JSONDecoder().decode([String].self, from: data)
            XCTAssertEqual(keyPoints.count, 3)
            XCTAssertEqual(reference.promptVersion, PromptCatalog.refineVersion)
        }
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
    func testLongImportPersistsFiftyAndTwoRefinementBatches() async throws {
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
        XCTAssertEqual(run.refinementBatches.sorted(by: { $0.ordinal < $1.ordinal }).map(\.candidateCount), [50, 2])
        XCTAssertEqual(run.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 52)
    }

    @MainActor
    func testFailedRefinementActivatesNothingAndContinueUsesSameSource() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let failing = makeCoordinator(
            context: context,
            client: StubAIClient(mode: .refineAlwaysFail)
        )

        let runID = try await failing.start(markdown: Self.sampleMarkdown, fileName: "sample-interview.md")
        let sourceID = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportRunRecord>()).first?.sourceDocument.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ImportRunRecord>()).first?.status, .failed)

        let succeeding = makeCoordinator(context: context, client: StubAIClient())
        try await succeeding.continueRun(id: runID)

        let completedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ImportRunRecord>()).first)
        XCTAssertEqual(completedRun.sourceDocument.id, sourceID)
        XCTAssertEqual(completedRun.status, .active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocumentRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 3)
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
    func testInvalidAnswerRejectsWholeRefinementBatchBeforeCandidateMutation() async throws {
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
        XCTAssertEqual(run.status, .failed)
        XCTAssertTrue(run.errorSummary?.contains("少于 120") == true)
        XCTAssertTrue(run.chunks.flatMap(\.candidates).allSatisfy { $0.status == .pending })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)
    }

    @MainActor
    func testActivationRevalidatesPersistedRefinedAnswerBeforeCreatingCards() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let failing = makeCoordinator(
            context: context,
            client: StubAIClient(mode: .refineAlwaysFail)
        )
        let runID = try await failing.start(markdown: Self.sampleMarkdown, fileName: "activation-bypass.md")
        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        let candidate = try XCTUnwrap(run.chunks.flatMap(\.candidates).first)
        candidate.status = .refined
        candidate.proposedAnswerText = "只有泛泛定义。"
        for batch in run.refinementBatches {
            batch.status = .completed
        }
        try context.save()

        let continuing = makeCoordinator(context: context, client: StubAIClient())
        try await continuing.continueRun(id: runID)

        XCTAssertEqual(run.status, .failed)
        XCTAssertTrue(run.errorSummary?.contains("少于 120") == true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)
    }

    @MainActor
    private func makeCoordinator(
        context: ModelContext,
        client: any AIClient
    ) -> ImportCoordinator {
        ImportCoordinator(
            context: context,
            aiClient: client,
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 1_200, overlapCharacters: 180)),
            diagnostics: .init(isEnabled: false),
            importsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("InterviewFlashcardImportTests", isDirectory: true),
            retryDelayNanoseconds: 0,
            now: { Fixtures.now }
        )
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
