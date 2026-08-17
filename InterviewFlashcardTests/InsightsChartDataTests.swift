import Foundation
import XCTest

final class InsightsChartDataTests: XCTestCase {
    func testChartDataUsesSnapshotValuesAndKeepsDifferentUnitsSeparate() {
        let now = Fixtures.now
        let topicID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let cards = (1...3).map { index in
            InsightsAggregator.CardInput(
                id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index))!,
                topicID: topicID,
                topicName: "后端"
            )
        }
        let dimensions = DimensionScores(correctness: 80, coverage: 60, reasoning: 70, structure: 90, tradeoffs: 50, precision: 100)
        let attempts = [
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[0].id, submittedAt: now.addingTimeInterval(-86_400),
                evaluation: .init(totalScore: 70, dimensions: dimensions)
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[0].id, submittedAt: now,
                evaluation: .init(totalScore: 90, dimensions: dimensions)
            ),
            InsightsAggregator.AttemptInput(
                id: UUID(), questionID: cards[1].id, submittedAt: now,
                evaluation: nil
            ),
        ]
        let snapshot = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: cards,
            attempts: attempts
        )

        XCTAssertEqual(InsightsChartData.coverageSegments(from: snapshot).map(\.value), [2, 1])
        XCTAssertEqual(InsightsChartData.scoreMetrics(from: snapshot).map(\.value), [80, 90, 90])
        XCTAssertEqual(InsightsChartData.activityMetrics(from: snapshot).map(\.value), [3, 2, 1, 2, 3, 3])
        XCTAssertEqual(InsightsChartData.dimensionMetrics(from: snapshot).map(\.value), [80, 60, 70, 90, 50, 100])
        XCTAssertEqual(InsightsChartData.topicMetrics(from: snapshot).count, 2)
        XCTAssertEqual(InsightsChartData.trendMetrics(from: snapshot).count, 2)
        XCTAssertEqual(InsightsChartData.trendMetrics(from: snapshot).map(\.answerCount), [1, 2])

        let heatmap = InsightsChartData.activityHeatmapMetrics(
            from: snapshot,
            asOf: now,
            calendar: Fixtures.calendar,
            dayCount: 3
        )
        XCTAssertEqual(heatmap.map(\.answerCount), [0, 1, 2])
        XCTAssertEqual(heatmap.count, 3)
    }

    func testChartDataDoesNotInventValuesForEmptyOrUnscoredSnapshot() {
        let now = Fixtures.now
        let topicID = UUID()
        let card = InsightsAggregator.CardInput(id: UUID(), topicID: topicID, topicName: "后端")
        let unscoredAttempt = InsightsAggregator.AttemptInput(id: UUID(), questionID: card.id, submittedAt: now)
        let snapshot = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: [card],
            attempts: [unscoredAttempt]
        )

        XCTAssertTrue(InsightsChartData.scoreMetrics(from: snapshot).isEmpty)
        XCTAssertTrue(InsightsChartData.dimensionMetrics(from: snapshot).isEmpty)
        XCTAssertEqual(InsightsChartData.activityMetrics(from: snapshot).map(\.value), [1, 0, 1, 1, 1, 1])
        XCTAssertEqual(InsightsChartData.trendMetrics(from: snapshot).count, 1)
        XCTAssertNil(InsightsChartData.trendMetrics(from: snapshot).first?.averageScore)
        XCTAssertEqual(
            InsightsChartData.activityHeatmapMetrics(
                from: snapshot,
                asOf: now,
                calendar: Fixtures.calendar,
                dayCount: 2
            ).map(\.answerCount),
            [0, 1]
        )

        let empty = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: [InsightsAggregator.CardInput](),
            attempts: [InsightsAggregator.AttemptInput]()
        )
        XCTAssertTrue(InsightsChartData.coverageSegments(from: empty).isEmpty)
        XCTAssertTrue(InsightsChartData.scoreMetrics(from: empty).isEmpty)
        XCTAssertTrue(InsightsChartData.activityMetrics(from: empty).isEmpty)
        XCTAssertTrue(InsightsChartData.dimensionMetrics(from: empty).isEmpty)
        XCTAssertTrue(InsightsChartData.topicMetrics(from: empty).isEmpty)
        XCTAssertTrue(InsightsChartData.trendMetrics(from: empty).isEmpty)
        XCTAssertTrue(
            InsightsChartData.activityHeatmapMetrics(
                from: empty,
                asOf: now,
                calendar: Fixtures.calendar,
                dayCount: 30
            ).isEmpty
        )

        let oldAttempt = InsightsAggregator.AttemptInput(
            id: UUID(),
            questionID: card.id,
            submittedAt: now.addingTimeInterval(-90 * 86_400)
        )
        let oldSnapshot = InsightsAggregator().snapshot(
            asOf: now,
            calendar: Fixtures.calendar,
            cards: [card],
            attempts: [oldAttempt]
        )
        XCTAssertTrue(
            InsightsChartData.activityHeatmapMetrics(
                from: oldSnapshot,
                asOf: now,
                calendar: Fixtures.calendar,
                dayCount: 30
            ).isEmpty
        )
    }
}
