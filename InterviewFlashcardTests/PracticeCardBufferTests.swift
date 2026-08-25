import Foundation
import XCTest

final class PracticeCardBufferTests: XCTestCase {
    private let topicID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    func testInitialRandomProductionFillsFiveUniqueUpcomingCards() {
        let cards = (1...8).map { snapshot(ordinal: $0) }
        let request = request(
            snapshots: cards,
            desiredCount: PracticeCardBuffer.capacity,
            seededGenerator: SeededPracticeRandomNumberGenerator(seed: 42)
        )

        let result = PracticeCardProducer().produce(request)

        XCTAssertEqual(result.cards.count, 5)
        XCTAssertEqual(Set(result.cards.map(\.id)).count, 5)
    }

    func testConsumeIsFIFOAndOneReplacementRestoresCapacity() {
        let cards = (1...6).map { snapshot(ordinal: $0) }
        var buffer = PracticeCardBuffer()
        buffer.reset(generation: 1)
        XCTAssertTrue(buffer.apply(.init(generation: 1, cards: Array(cards.prefix(5)))))

        XCTAssertEqual(buffer.consume()?.id, cards[0].id)
        XCTAssertEqual(buffer.count, 4)

        XCTAssertTrue(buffer.apply(.init(generation: 1, cards: [cards[5]])))
        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.upcoming.map(\.id), Array(cards[1...5]).map(\.id))
    }

    func testRandomReplacementExcludesCurrentAndAlreadyQueuedCards() {
        let cards = (1...7).map { snapshot(ordinal: $0) }
        let request = request(
            snapshots: cards,
            currentQuestionID: cards[0].id,
            queuedQuestionIDs: Set(cards[1...4].map(\.id)),
            desiredCount: 2,
            seededGenerator: SeededPracticeRandomNumberGenerator(seed: 7)
        )

        let result = PracticeCardProducer().produce(request)

        XCTAssertEqual(Set(result.cards.map(\.id)), Set(cards[5...6].map(\.id)))
    }

    func testOrderedProductionUsesGlobalQuestionNumberAfterProgress() {
        let cards = [
            snapshot(ordinal: 1, questionNumber: 30),
            snapshot(ordinal: 2, questionNumber: 10),
            snapshot(ordinal: 3, questionNumber: 20),
            snapshot(ordinal: 4, questionNumber: 40),
        ]

        let ascending = PracticeCardProducer().produce(request(
            snapshots: cards,
            orderMode: .ascending,
            progressQuestionID: cards[2].id,
            desiredCount: 2
        ))
        let descending = PracticeCardProducer().produce(request(
            snapshots: cards,
            orderMode: .descending,
            progressQuestionID: cards[2].id,
            desiredCount: 2
        ))

        XCTAssertEqual(ascending.cards.map(\.questionNumber), [30, 40])
        XCTAssertEqual(descending.cards.map(\.questionNumber), [10])
    }

    func testSmallRandomPoolAllowsSingleCardToRepeatButDoesNotQueueDuplicates() {
        let onlyCard = snapshot(ordinal: 1)

        let result = PracticeCardProducer().produce(request(
            snapshots: [onlyCard],
            currentQuestionID: onlyCard.id,
            desiredCount: 5
        ))

        XCTAssertEqual(result.cards.map(\.id), [onlyCard.id])
    }

    func testBufferRejectsProductionFromInvalidatedGeneration() {
        let card = snapshot(ordinal: 1)
        var buffer = PracticeCardBuffer()
        buffer.reset(generation: 2)

        XCTAssertFalse(buffer.apply(.init(generation: 1, cards: [card])))
        XCTAssertTrue(buffer.upcoming.isEmpty)
    }

    func testRebasePreservesStillEligiblePreparedCards() {
        let cards = (1...3).map { snapshot(ordinal: $0) }
        var buffer = PracticeCardBuffer()
        buffer.reset(generation: 1)
        XCTAssertTrue(buffer.apply(.init(generation: 1, cards: cards)))

        buffer.rebase(
            generation: 2,
            retaining: [cards[0].id, cards[2].id]
        )

        XCTAssertEqual(buffer.generation, 2)
        XCTAssertEqual(buffer.upcoming.map(\.id), [cards[0].id, cards[2].id])
    }

    private func request(
        snapshots: [QuestionCardSnapshot],
        orderMode: PracticeOrderMode = .random,
        progressQuestionID: UUID? = nil,
        currentQuestionID: UUID? = nil,
        queuedQuestionIDs: Set<UUID> = [],
        desiredCount: Int,
        seededGenerator: SeededPracticeRandomNumberGenerator? = nil
    ) -> PracticeCardProductionRequest {
        PracticeCardProductionRequest(
            generation: 1,
            snapshots: snapshots,
            selectedTopicIDs: [topicID],
            includePracticed: false,
            orderMode: orderMode,
            progressQuestionID: progressQuestionID,
            currentQuestionID: currentQuestionID,
            queuedQuestionIDs: queuedQuestionIDs,
            desiredCount: desiredCount,
            seededGenerator: seededGenerator
        )
    }

    private func snapshot(
        ordinal: Int,
        questionNumber: Int? = nil
    ) -> QuestionCardSnapshot {
        QuestionCardSnapshot(
            id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", ordinal))!,
            topicID: topicID,
            topicName: "后端",
            questionText: "题目 \(ordinal)",
            questionNumber: questionNumber,
            isTrashed: false,
            hasSubmittedAttempt: false
        )
    }
}
