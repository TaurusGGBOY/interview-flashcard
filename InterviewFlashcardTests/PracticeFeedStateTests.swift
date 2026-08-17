import Foundation
import XCTest

final class PracticeFeedStateTests: XCTestCase {
    private let firstID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
    private let topicID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    func testInitialStateUsesUnpracticedDefaultWithoutSessionLimit() {
        let state = PracticeFeedState()

        XCTAssertNil(state.currentQuestionID)
        XCTAssertTrue(state.selectedTopicIDs.isEmpty)
        XCTAssertFalse(state.includePracticed)
        XCTAssertNil(state.lastAction)
    }

    func testPresentThenSkipClearsCurrentWithoutPermanentlyExcludingQuestion() {
        var state = PracticeFeedState(
            selectedTopicIDs: [topicID],
            includePracticed: false
        )

        state.present(questionID: firstID)
        XCTAssertEqual(state.currentQuestionID, firstID)

        XCTAssertEqual(state.skipCurrent(), firstID)
        XCTAssertNil(state.currentQuestionID)
        XCTAssertEqual(state.lastAction, .skipped(questionID: firstID))

        state.present(questionID: firstID)
        XCTAssertEqual(state.currentQuestionID, firstID)
    }

    func testAnswerClearsCurrentAndRecordsUndoableAnswerWithoutPersistenceMutation() {
        var state = PracticeFeedState(
            selectedTopicIDs: [topicID],
            includePracticed: false
        )
        state.present(questionID: firstID)

        XCTAssertEqual(state.answerCurrent(), firstID)
        XCTAssertNil(state.currentQuestionID)
        XCTAssertEqual(state.lastAction, .answered(questionID: firstID))

        XCTAssertEqual(state.undoLastSwipe(), firstID)
        XCTAssertEqual(state.currentQuestionID, firstID)
        XCTAssertNil(state.lastAction)
    }

    func testUndoRestoresOnlyMostRecentSwipeAndDoesNotRequireRemovingAnAnswer() {
        var state = PracticeFeedState()
        state.present(questionID: firstID)
        _ = state.skipCurrent()
        state.present(questionID: secondID)

        XCTAssertEqual(state.undoLastSwipe(), firstID)
        XCTAssertEqual(state.currentQuestionID, firstID)
        XCTAssertNil(state.lastAction)
        XCTAssertNil(state.undoLastSwipe())
    }

    func testEmptyReasonDistinguishesLibrarySelectionAndConfiguredPool() {
        let emptySelection = PracticeFeedState()
        let selected = PracticeFeedState(selectedTopicIDs: [topicID])

        XCTAssertEqual(
            emptySelection.emptyReason(totalActiveCount: 0, eligibleCount: 0),
            .globalLibraryEmpty
        )
        XCTAssertEqual(
            emptySelection.emptyReason(totalActiveCount: 4, eligibleCount: 0),
            .noTopicsSelected
        )
        XCTAssertEqual(
            selected.emptyReason(totalActiveCount: 4, eligibleCount: 0),
            .filteredPoolEmpty
        )
        XCTAssertNil(selected.emptyReason(totalActiveCount: 4, eligibleCount: 2))
    }

    func testTopicAndPracticedFiltersAreMutableConfigurationOnly() {
        var state = PracticeFeedState()
        state.selectedTopicIDs = [topicID]
        state.includePracticed = true

        XCTAssertEqual(state.selectedTopicIDs, [topicID])
        XCTAssertTrue(state.includePracticed)
    }
}
