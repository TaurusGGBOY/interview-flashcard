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
            return "## Q\(number) 唯一问题\n\n- 关键点 A\n- 关键点 B\n\nQ\(number) 的唯一来源说明。\n"
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

    JVM 类加载包括加载、验证、准备、解析和初始化，初始化阶段执行类构造器。

    ## HashMap 扩容

    HashMap 达到阈值后扩容，迁移元素时利用容量为二次幂的性质确定新位置。

    ```swift
    let text = "## 这不是题目"
    print(text)
    ```

    ## CAP 取舍

    网络分区发生时，分布式系统需要在一致性和可用性之间作出取舍。
    """
}
