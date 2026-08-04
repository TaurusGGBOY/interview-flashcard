import Foundation
import XCTest
@testable import InterviewFlashcard

final class InsightsAggregatorTests: XCTestCase {
    func testInsightsSeparatesCoverageFromAttemptCount() {
        let now = Fixtures.now
        let cards = (1...4).map { index in
            InsightsAggregator.CardInput(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index))!,
                topicID: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                topicName: "后端"
            )
        }
        let scores = DimensionScores(correctness: 80, coverage: 60, reasoning: 80, structure: 80, tradeoffs: 70, precision: 100)
        let evaluation = InsightsAggregator.EvaluationInput(totalScore: 75, dimensions: scores)
        let attempts = [
            InsightsAggregator.AttemptInput(id: UUID(), questionID: cards[0].id, submittedAt: now.addingTimeInterval(-86_400), evaluation: evaluation),
            InsightsAggregator.AttemptInput(id: UUID(), questionID: cards[1].id, submittedAt: now.addingTimeInterval(-86_400), evaluation: evaluation),
            InsightsAggregator.AttemptInput(id: UUID(), questionID: cards[0].id, submittedAt: now, evaluation: evaluation),
        ]

        let snapshot = InsightsAggregator().snapshot(asOf: now, calendar: Fixtures.calendar, cards: cards, attempts: attempts)
        XCTAssertEqual(snapshot.totalCards, 4)
        XCTAssertEqual(snapshot.practicedCards, 2)
        XCTAssertEqual(snapshot.unpracticedCards, 2)
        XCTAssertEqual(snapshot.coverageRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.answerCount, 3)
        XCTAssertEqual(snapshot.practiceDays, 2)
        XCTAssertEqual(snapshot.averageScore, 75)
        XCTAssertEqual(snapshot.averageDimensions, scores)
    }

    func testTrashedCardDoesNotAffectCoverageOrScores() {
        let card = InsightsAggregator.CardInput(id: UUID(), topicID: UUID(), topicName: "后端", isTrashed: true)
        let attempt = InsightsAggregator.AttemptInput(id: UUID(), questionID: card.id, submittedAt: Fixtures.now, evaluation: nil)
        let snapshot = InsightsAggregator().snapshot(asOf: Fixtures.now, calendar: Fixtures.calendar, cards: [card], attempts: [attempt])
        XCTAssertEqual(snapshot.totalCards, 0)
        XCTAssertEqual(snapshot.answerCount, 0)
        XCTAssertEqual(snapshot.coverageRate, 0)
    }
}
