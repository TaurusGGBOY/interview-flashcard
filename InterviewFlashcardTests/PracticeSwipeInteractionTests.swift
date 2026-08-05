import CoreGraphics
import Foundation
import XCTest

final class PracticeSwipeInteractionTests: XCTestCase {
    func testShortHorizontalDragReturnsNil() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 70, height: 4),
            predictedEndTranslation: CGSize(width: 80, height: 4),
            cardWidth: 300
        )

        XCTAssertNil(action)
    }

    func testLeftDragPastThresholdSkips() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: -100, height: 8),
            predictedEndTranslation: CGSize(width: -110, height: 8),
            cardWidth: 300
        )

        XCTAssertEqual(action, .skip)
    }

    func testRightDragPastThresholdStartsAnswer() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 100, height: 8),
            predictedEndTranslation: CGSize(width: 110, height: 8),
            cardWidth: 300
        )

        XCTAssertEqual(action, .answer)
    }

    func testVerticalDragNeverCommits() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 120, height: 180),
            predictedEndTranslation: CGSize(width: 220, height: 280),
            cardWidth: 300
        )

        XCTAssertNil(action)
    }

    func testFastHorizontalProjectionCommitsBelowDistanceThreshold() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 42, height: 5),
            predictedEndTranslation: CGSize(width: 150, height: 8),
            cardWidth: 300
        )

        XCTAssertEqual(action, .answer)
    }

    func testNextDrawPoolExcludesCurrentWhenAlternativesExist() {
        let first = snapshot(ordinal: 1)
        let second = snapshot(ordinal: 2)

        let pool = PracticeSwipeInteraction.nextDrawPool(
            from: [first, second],
            excluding: first.id
        )

        XCTAssertEqual(pool, [second])
    }

    func testNextDrawPoolFallsBackWhenCurrentIsOnlyCard() {
        let onlyCard = snapshot(ordinal: 1)

        let pool = PracticeSwipeInteraction.nextDrawPool(
            from: [onlyCard],
            excluding: onlyCard.id
        )

        XCTAssertEqual(pool, [onlyCard])
    }

    private func snapshot(ordinal: Int) -> QuestionCardSnapshot {
        QuestionCardSnapshot(
            id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", ordinal))!,
            topicID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            topicName: "后端",
            questionText: "题目 \(ordinal)",
            isTrashed: false,
            hasSubmittedAttempt: false
        )
    }
}
