import SwiftData
import XCTest

final class ReclassificationServiceTests: XCTestCase {
    @MainActor
    func testReclassificationUsesFiftyCardBatchesAndSkipsFailedBatch() async throws {
        let fixture = try ReclassificationFixture.make(
            othersCount: 103,
            topicNames: ["Java", "Go"],
            failedCalls: [2]
        )
        let before = fixture.contentSnapshot()

        let summary = await fixture.service.runAllOthers(context: fixture.context)

        let batchSizes = await fixture.ai.batchSizes
        XCTAssertEqual(batchSizes.sorted(), [3, 50, 50])
        XCTAssertEqual(summary.totalCards, 103)
        XCTAssertEqual(summary.succeededBatches, 2)
        XCTAssertEqual(summary.failedBatches, 1)
        XCTAssertTrue([3, 50].contains(summary.remainingOthersCards))
        XCTAssertNil(summary.fatalErrorMessage)
        XCTAssertEqual(fixture.contentSnapshot(), before, "重新分类只能修改 Topic")

        let runs = try fixture.context.fetch(FetchDescriptor<ReclassificationRunRecord>())
        let run = try XCTUnwrap(runs.first)
        XCTAssertEqual(run.status, .completedWithFailures)
        XCTAssertEqual(run.totalCards, 103)
        XCTAssertEqual(run.reclassifiedCards + run.failedCards, 103)
        XCTAssertEqual(run.failedCards, summary.remainingOthersCards)
        XCTAssertNotNil(run.completedAt)
        XCTAssertEqual(run.batches.filter { $0.status == .failed }.count, 1)
    }

    @MainActor
    func testReclassificationUsesBoundedConcurrencyForFourBatches() async throws {
        let fixture = try ReclassificationFixture.make(
            othersCount: 151,
            topicNames: ["Swift"],
            delayNanoseconds: 20_000_000
        )

        let summary = await fixture.service.runAllOthers(context: fixture.context)

        let batchSizes = await fixture.ai.batchSizes
        let maximumActive = await fixture.ai.maximumActiveCalls()
        let run = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<ReclassificationRunRecord>()).first
        )
        XCTAssertEqual(batchSizes.sorted(), [1, 50, 50, 50])
        XCTAssertLessThanOrEqual(maximumActive, 3)
        XCTAssertEqual(summary.totalCards, 151)
        XCTAssertEqual(summary.succeededBatches, 4)
        XCTAssertEqual(summary.failedBatches, 0)
        XCTAssertEqual(run.reclassifiedCards, 151)
        XCTAssertEqual(summary.remainingOthersCards, 0)
        XCTAssertTrue(fixture.cards.allSatisfy { $0.topic.systemKind != .others })
    }

    @MainActor
    func testUnknownTopicFailsBatchWithoutSilentlyReportingSuccess() async throws {
        let fixture = try ReclassificationFixture.make(
            othersCount: 1,
            topicNames: ["Swift"],
            responseMode: .unknownTopic
        )

        let summary = await fixture.service.runAllOthers(context: fixture.context)

        XCTAssertEqual(summary.succeededBatches, 0)
        XCTAssertEqual(summary.failedBatches, 1)
        XCTAssertEqual(summary.remainingOthersCards, 1)
        XCTAssertEqual(try fixture.activeOthersCount(), 1)
    }

    @MainActor
    func testIncompleteAssignmentsFailOnlyThatBatch() async throws {
        let fixture = try ReclassificationFixture.make(
            othersCount: 51,
            topicNames: ["Swift"],
            responseMode: .omitLastAssignment
        )

        let summary = await fixture.service.runAllOthers(context: fixture.context)

        let batchSizes = await fixture.ai.batchSizes
        XCTAssertEqual(batchSizes.sorted(), [1, 50])
        XCTAssertEqual(summary.succeededBatches, 0)
        XCTAssertEqual(summary.failedBatches, 2)
        XCTAssertEqual(summary.remainingOthersCards, 51)
        let run = try XCTUnwrap(
            try fixture.context.fetch(FetchDescriptor<ReclassificationRunRecord>()).first
        )
        XCTAssertEqual(run.batches.map(\.status), [.failed, .failed])
    }

    @MainActor
    func testTrashedCardsAreNotIncludedInSnapshot() async throws {
        let fixture = try ReclassificationFixture.make(
            othersCount: 2,
            topicNames: ["Swift"]
        )
        fixture.cards[0].trashedAt = Fixtures.now
        try fixture.context.save()

        let summary = await fixture.service.runAllOthers(context: fixture.context)

        let batchSizes = await fixture.ai.batchSizes
        XCTAssertEqual(batchSizes, [1])
        XCTAssertEqual(summary.totalCards, 1)
        XCTAssertEqual(summary.remainingOthersCards, 0)
        XCTAssertEqual(fixture.cards[0].topic.systemKind, .others)
    }
}

@MainActor
private struct ReclassificationFixture {
    struct ContentSnapshot: Equatable {
        let questions: [UUID: String]
        let answers: [UUID: [String]]
        let updatedAt: [UUID: Date]
    }

    let context: ModelContext
    let ai: ReclassificationAIStub
    let service: ReclassificationService
    let cards: [QuestionCardRecord]

    static func make(
        othersCount: Int,
        topicNames: [String],
        failedCalls: Set<Int> = [],
        responseMode: ReclassificationAIStub.ResponseMode = .firstAvailableTopic,
        delayNanoseconds: UInt64 = 0
    ) throws -> ReclassificationFixture {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let topicService = TopicService()
        for name in topicNames {
            _ = try topicService.create(name: name, context: context, now: Fixtures.now)
        }
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>())
                .first(where: { $0.systemKind == .others })
        )
        let source = SourceDocumentRecord(
            fileName: "reclassification-fixture.md",
            contentHash: UUID().uuidString,
            importerVersion: "test",
            importedAt: Fixtures.now
        )
        context.insert(source)

        let cards = (0..<othersCount).map { index in
            let card = QuestionCardRecord(
                questionText: "题目 \(index)",
                sourceAnchor: "fixture.md#q\(index)",
                createdAt: Fixtures.now,
                updatedAt: Fixtures.now,
                activatedAt: Fixtures.now,
                topic: others,
                sourceDocument: source
            )
            context.insert(card)
            context.insert(
                ReferenceAnswerVersionRecord(
                    version: 1,
                    answerText: "满分答案 \(index)",
                    createdAt: Fixtures.now,
                    question: card
                )
            )
            return card
        }
        try context.save()

        let ai = ReclassificationAIStub(
            failedCalls: failedCalls,
            responseMode: responseMode,
            delayNanoseconds: delayNanoseconds
        )
        return ReclassificationFixture(
            context: context,
            ai: ai,
            service: ReclassificationService(aiClient: ai, now: { Fixtures.now }),
            cards: cards
        )
    }

    func activeOthersCount() throws -> Int {
        try context.fetch(FetchDescriptor<QuestionCardRecord>())
            .filter { !$0.isTrashed && $0.topic.systemKind == .others }
            .count
    }

    func contentSnapshot() -> ContentSnapshot {
        ContentSnapshot(
            questions: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.questionText) }),
            answers: Dictionary(
                uniqueKeysWithValues: cards.map { card in
                    (card.id, card.referenceAnswers.sorted { $0.version < $1.version }.map(\.answerText))
                }
            ),
            updatedAt: Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.updatedAt) })
        )
    }
}

private actor ReclassificationAIStub: AIClient {
    enum ResponseMode: Equatable, Sendable {
        case firstAvailableTopic
        case unknownTopic
        case omitLastAssignment
    }

    private let failedCalls: Set<Int>
    private let responseMode: ResponseMode
    private let delayNanoseconds: UInt64
    private var activeCalls = 0
    private var maximumActive = 0
    private(set) var batchSizes: [Int] = []

    init(
        failedCalls: Set<Int>,
        responseMode: ResponseMode,
        delayNanoseconds: UInt64
    ) {
        self.failedCalls = failedCalls
        self.responseMode = responseMode
        self.delayNanoseconds = delayNanoseconds
    }

    func maximumActiveCalls() -> Int {
        maximumActive
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        activeCalls += 1
        maximumActive = max(maximumActive, activeCalls)
        defer { activeCalls -= 1 }
        batchSizes.append(request.cards.count)
        let batchOrdinal = batchSizes.count
        if failedCalls.contains(batchOrdinal) {
            throw AIError.invalidResponse("Injected failure for batch \(batchOrdinal)")
        }
        try await Task.sleep(nanoseconds: delayNanoseconds)

        let topicName: String
        switch responseMode {
        case .firstAvailableTopic, .omitLastAssignment:
            topicName = request.availableTopicNames.first(where: { $0 != "Others" })
                ?? request.availableTopicNames.first
                ?? "Others"
        case .unknownTopic:
            topicName = "Unknown Topic"
        }
        var assignments = request.cards.map {
            ReclassificationAssignment(cardID: $0.id, topicName: topicName)
        }
        if responseMode == .omitLastAssignment, !assignments.isEmpty {
            assignments.removeLast()
        }
        return ReclassifyResponse(assignments: assignments, completionStatus: .complete)
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        throw AIError.invalidResponse("Unused test method")
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        throw AIError.invalidResponse("Unused test method")
    }
}
