import Foundation
import XCTest

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

    func testTopicScopeIsolatesMetricsAndKeepsAllTopicSummaries() {
        let now = Fixtures.now
        let backendID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let mobileID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        let cards = [
            InsightsAggregator.CardInput(id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!, topicID: backendID, topicName: "后端"),
            InsightsAggregator.CardInput(id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!, topicID: backendID, topicName: "后端"),
            InsightsAggregator.CardInput(id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!, topicID: mobileID, topicName: "移动端"),
            InsightsAggregator.CardInput(id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!, topicID: mobileID, topicName: "移动端"),
            InsightsAggregator.CardInput(id: UUID(uuidString: "30000000-0000-0000-0000-000000000005")!, topicID: mobileID, topicName: "移动端", isTrashed: true),
        ]
        let backendScores = DimensionScores(correctness: 80, coverage: 70, reasoning: 60, structure: 90, tradeoffs: 50, precision: 100)
        let secondBackendScores = DimensionScores(correctness: 60, coverage: 50, reasoning: 40, structure: 70, tradeoffs: 30, precision: 80)
        let mobileScores = DimensionScores(correctness: 40, coverage: 40, reasoning: 40, structure: 40, tradeoffs: 40, precision: 40)
        let attempts = [
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[0].id, submittedAt: now.addingTimeInterval(-86_400),
                evaluation: .init(totalScore: 80, dimensions: backendScores)
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[1].id, submittedAt: now,
                evaluation: .init(totalScore: 60, dimensions: secondBackendScores)
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[0].id, submittedAt: now,
                evaluation: nil
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[2].id, submittedAt: now,
                evaluation: .init(totalScore: 40, dimensions: mobileScores)
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[3].id, submittedAt: now,
                evaluation: .init(totalScore: nil, dimensions: mobileScores, status: .scoring)
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[4].id, submittedAt: now,
                evaluation: .init(totalScore: 100, dimensions: mobileScores)
            ),
        ]

        let all = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: cards,
            attempts: attempts,
            scope: .all
        )
        let backend = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: cards,
            attempts: attempts,
            scope: .topic(backendID)
        )
        let mobile = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: cards,
            attempts: attempts,
            scope: .topic(mobileID)
        )

        XCTAssertEqual(all.totalCards, 4)
        XCTAssertEqual(all.answerCount, 5)
        XCTAssertEqual(all.scoredAnswerCount, 3)
        XCTAssertEqual(all.topicSummaries.count, 2)

        XCTAssertEqual(backend.scope, .topic(backendID))
        XCTAssertEqual(backend.totalCards, 2)
        XCTAssertEqual(backend.practicedCards, 2)
        XCTAssertEqual(backend.coverageRate, 1, accuracy: 0.0001)
        XCTAssertEqual(backend.answerCount, 3)
        XCTAssertEqual(backend.scoredAnswerCount, 2)
        XCTAssertEqual(backend.unscoredAnswerCount, 1)
        XCTAssertEqual(backend.sevenDayAnswerCount, 3)
        XCTAssertEqual(backend.thirtyDayAnswerCount, 3)
        XCTAssertEqual(backend.practiceDays, 2)
        XCTAssertEqual(backend.averageScore, 70)
        XCTAssertEqual(backend.averageDimensions, DimensionScores(correctness: 70, coverage: 60, reasoning: 50, structure: 80, tradeoffs: 40, precision: 90))
        XCTAssertEqual(backend.trend.count, 2)

        XCTAssertEqual(mobile.totalCards, 2)
        XCTAssertEqual(mobile.practicedCards, 2)
        XCTAssertEqual(mobile.answerCount, 2)
        XCTAssertEqual(mobile.scoredAnswerCount, 1)
        XCTAssertEqual(mobile.unscoredAnswerCount, 1)
        XCTAssertEqual(mobile.averageScore, 40)
        XCTAssertEqual(mobile.averageDimensions, mobileScores)
        XCTAssertEqual(mobile.trend.count, 1)

        let backendSummary = all.topicSummaries.first { $0.id == backendID }
        XCTAssertEqual(backendSummary?.cardCount, 2)
        XCTAssertEqual(backendSummary?.practicedCards, 2)
        XCTAssertEqual(backendSummary?.averageScore, 70)
    }

    func testTopicScopeWithUnknownTopicReturnsEmptyMetrics() {
        let card = InsightsAggregator.CardInput(id: UUID(), topicID: UUID(), topicName: "后端")
        let attempt = InsightsAggregator.AttemptInput(id: UUID(), questionID: card.id, submittedAt: Fixtures.now)
        let unknownTopicID = UUID()

        let snapshot = InsightsAggregator().snapshot(
            asOf: Fixtures.now,
            calendar: Fixtures.calendar,
            cards: [card],
            attempts: [attempt],
            scope: .topic(unknownTopicID)
        )

        XCTAssertEqual(snapshot.scope, .topic(unknownTopicID))
        XCTAssertEqual(snapshot.totalCards, 0)
        XCTAssertEqual(snapshot.answerCount, 0)
        XCTAssertEqual(snapshot.trend, [])
        XCTAssertEqual(snapshot.topicSummaries.count, 1)
    }
}
