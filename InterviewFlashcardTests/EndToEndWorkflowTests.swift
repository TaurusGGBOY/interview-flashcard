import Foundation
import SwiftData
import XCTest

final class EndToEndWorkflowTests: XCTestCase {
    @MainActor
    func testFullLocalWorkflowFromImportThroughStatistics() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)

        let java = try TopicService().create(name: "Java", context: context, now: Fixtures.now)
        let importer = ImportCoordinator(
            context: context,
            aiClient: StubAIClient(),
            chunker: MarkdownChunker(configuration: .init(targetCharacters: 1_200, overlapCharacters: 180)),
            diagnostics: .init(isEnabled: false),
            importsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("InterviewFlashcardEndToEnd", isDirectory: true),
            retryDelayNanoseconds: 0,
            now: { Fixtures.now }
        )

        let runID = try await importer.start(markdown: Self.sampleMarkdown, fileName: "e2e-interview.md")
        let run = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ImportRunRecord>()).first(where: { $0.id == runID })
        )
        XCTAssertEqual(run.status, .active)

        let card = try XCTUnwrap(run.sourceDocument.cards.first)
        card.topic = java
        try context.save()

        _ = try await ReferenceAnswerService(
            aiClient: StubAIClient(),
            now: { Fixtures.now }
        ).ensureReferenceAnswer(questionID: card.id, context: context)

        let attempt = try AnswerSubmissionService(now: { Fixtures.now }).submitText(
            questionID: card.id,
            rawText: "类加载包括加载、验证和初始化。",
            context: context
        )
        let evaluation = try await AnswerProcessingService(
            aiClient: RetryingAIClient(base: StubAIClient(), retryDelayNanoseconds: 0),
            now: { Fixtures.now }
        ).process(attemptID: attempt.id, context: context)

        let history = try HistoryQuery(context: context).global()
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let attempts = try context.fetch(FetchDescriptor<AnswerAttemptRecord>())
        let snapshot = InsightsAggregator().snapshot(
            asOf: Fixtures.now,
            calendar: Fixtures.calendar,
            cards: cards,
            attempts: attempts
        )

        XCTAssertEqual(history.map(\.id), [attempt.id])
        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertTrue(attempt.polishResults.isEmpty)
        XCTAssertEqual(attempt.evaluations.count, 1)
        XCTAssertNil(evaluation.polishResultID)
        XCTAssertEqual(evaluation.totalScore, 75)
        XCTAssertEqual(attempt.referenceAnswerTextSnapshot, card.referenceAnswers.first?.answerText)
        XCTAssertEqual(snapshot.totalCards, cards.count)
        XCTAssertEqual(snapshot.practicedCards, 1)
        XCTAssertEqual(snapshot.answerCount, 1)
        XCTAssertEqual(snapshot.averageScore, 75)
        XCTAssertTrue(snapshot.topicSummaries.contains(where: { $0.name == "Java" }))
    }

    @MainActor
    func testLaunchRecoveryIsIdempotentForPendingAttempt() async throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let card = try Fixtures.makeCard(context: context)
        let attempt = try AnswerSubmissionService(now: { Fixtures.now }).submitText(
            questionID: card.id,
            rawText: "回答内容",
            context: context
        )
        let processing = AnswerProcessingService(
            aiClient: RetryingAIClient(base: StubAIClient(), retryDelayNanoseconds: 0),
            now: { Fixtures.now }
        )
        let recovery = LaunchRecoveryCoordinator(processing: processing)

        await recovery.resume(context: context)
        await recovery.resume(context: context)

        XCTAssertEqual(attempt.processingStatus, .completed)
        XCTAssertTrue(attempt.polishResults.isEmpty)
        XCTAssertEqual(attempt.evaluations.count, 1)
    }

    private static let sampleMarkdown = """
    # Java 面试题

    ## 类加载阶段

    类加载包括加载、验证、准备、解析和初始化，初始化阶段执行类构造器。

    ## 双亲委派

    类加载器按层次委派，优先交给父加载器尝试加载。
    """
}
