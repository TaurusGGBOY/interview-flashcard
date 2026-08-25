import Foundation
import XCTest

final class QuestionDrawServiceTests: XCTestCase {
    private let backendID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let iosID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

    func testDefaultPoolExcludesPracticedButKeepsViewedOrSkippedCards() {
        let cards = [
            snapshot(ordinal: 1, topicID: backendID, practiced: true),
            snapshot(ordinal: 2, topicID: backendID),
            snapshot(ordinal: 3, topicID: backendID),
        ]

        let result = QuestionDrawService().eligibleCards(
            cards,
            topicIDs: [backendID],
            includePracticed: false
        )

        XCTAssertEqual(result.map(\.id), [cards[1].id, cards[2].id])
    }

    func testIncludePracticedAddsSubmittedCards() {
        let cards = [
            snapshot(ordinal: 1, topicID: backendID, practiced: true),
            snapshot(ordinal: 2, topicID: backendID),
        ]

        let result = QuestionDrawService().eligibleCards(
            cards,
            topicIDs: [backendID],
            includePracticed: true
        )

        XCTAssertEqual(result, cards)
    }

    func testEligibilityUsesAnySelectedTopicAndExcludesTrash() {
        let cards = [
            snapshot(ordinal: 1, topicID: backendID),
            snapshot(ordinal: 2, topicID: iosID),
            snapshot(ordinal: 3, topicID: iosID, trashed: true),
        ]

        let result = QuestionDrawService().eligibleCards(
            cards,
            topicIDs: [backendID, iosID],
            includePracticed: false
        )

        XCTAssertEqual(result.map(\.id), [cards[0].id, cards[1].id])
    }

    func testEmptyTopicSelectionProducesEmptyPool() {
        let cards = [snapshot(ordinal: 1, topicID: backendID)]

        let result = QuestionDrawService().eligibleCards(
            cards,
            topicIDs: [],
            includePracticed: true
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testDrawUsesOneUniformIndexFromEntirePool() {
        let cards = (1...4).map { snapshot(ordinal: $0, topicID: backendID) }
        var generator = FixedDrawRandomNumberGenerator(value: 13_835_058_055_282_163_709)

        let drawn = QuestionDrawService().draw(from: cards, using: &generator)

        XCTAssertEqual(drawn?.id, cards[2].id)
        XCTAssertEqual(generator.callCount, 1)
    }

    func testDrawReturnsNilWithoutConsultingGeneratorForEmptyPool() {
        var generator = FixedDrawRandomNumberGenerator(value: 0)

        let drawn = QuestionDrawService().draw(from: [], using: &generator)

        XCTAssertNil(drawn)
        XCTAssertEqual(generator.callCount, 0)
    }

    func testSeededGeneratorProducesReproducibleDrawSequence() {
        let cards = (1...4).map { snapshot(ordinal: $0, topicID: backendID) }
        var first = SeededPracticeRandomNumberGenerator(seed: 20_260_804)
        var second = SeededPracticeRandomNumberGenerator(seed: 20_260_804)
        let service = QuestionDrawService()

        let firstSequence = (0..<8).compactMap { _ in
            service.draw(from: cards, using: &first)?.id
        }
        let secondSequence = (0..<8).compactMap { _ in
            service.draw(from: cards, using: &second)?.id
        }

        XCTAssertEqual(firstSequence, secondSequence)
        XCTAssertEqual(firstSequence.count, 8)
    }

    func testOrderedModesSortAllSelectedTopicsByQuestionNumber() {
        let cards = [
            snapshot(ordinal: 1, topicID: iosID, questionNumber: 20),
            snapshot(ordinal: 2, topicID: backendID, questionNumber: 3),
            snapshot(ordinal: 3, topicID: iosID, questionNumber: 11),
        ]
        let service = QuestionDrawService()

        XCTAssertEqual(
            service.orderedCards(from: cards, mode: .ascending).map(\.questionNumber),
            [3, 11, 20]
        )
        XCTAssertEqual(
            service.orderedCards(from: cards, mode: .descending).map(\.questionNumber),
            [20, 11, 3]
        )
    }

    private func snapshot(
        ordinal: Int,
        topicID: UUID,
        questionNumber: Int? = nil,
        practiced: Bool = false,
        trashed: Bool = false
    ) -> QuestionCardSnapshot {
        QuestionCardSnapshot(
            id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", ordinal))!,
            topicID: topicID,
            topicName: topicID == backendID ? "后端" : "iOS",
            questionText: "题目 \(ordinal)",
            questionNumber: questionNumber,
            isTrashed: trashed,
            hasSubmittedAttempt: practiced
        )
    }
}

private struct FixedDrawRandomNumberGenerator: RandomNumberGenerator {
    let value: UInt64
    private(set) var callCount = 0

    mutating func next() -> UInt64 {
        callCount += 1
        return value
    }
}
