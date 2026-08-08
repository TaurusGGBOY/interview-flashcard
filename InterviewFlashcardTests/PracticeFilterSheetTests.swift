import Foundation
import XCTest

final class PracticeFilterSheetTests: XCTestCase {
    private let firstTopicID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
    private let secondTopicID = UUID(uuidString: "71000000-0000-0000-0000-000000000002")!

    func testInitialFilterDefaultsToAllTopicsAndExcludesPracticedCards() {
        let selection = PracticeFilterSelection.initial

        XCTAssertTrue(selection.selectedTopicIDs.isEmpty)
        XCTAssertFalse(selection.includePracticed)
        XCTAssertFalse(
            Mirror(reflecting: selection).children.contains { $0.label == "sessionSize" }
        )
    }

    func testApplyingFilterCarriesOnlyTopicAndPracticedConfiguration() {
        let selection = PracticeFilterSelection(
            selectedTopicIDs: [firstTopicID, secondTopicID],
            includePracticed: true
        )

        var feed = PracticeFeedState(selectedTopicIDs: [firstTopicID])
        feed.present(questionID: UUID(uuidString: "72000000-0000-0000-0000-000000000001")!)
        PracticeView.applyFilter(selection, to: &feed)

        XCTAssertEqual(feed.selectedTopicIDs, [firstTopicID, secondTopicID])
        XCTAssertTrue(feed.includePracticed)
        XCTAssertEqual(feed.currentQuestionID, UUID(uuidString: "72000000-0000-0000-0000-000000000001")!)
    }

    func testEmptyFilterReasonCanBeReopenedWithoutChangingGlobalRoute() {
        let state = PracticeFeedState(selectedTopicIDs: [firstTopicID])

        XCTAssertEqual(
            state.emptyReason(totalActiveCount: 3, eligibleCount: 0),
            .filteredPoolEmpty
        )
        XCTAssertEqual(RootTabView.globalEmptyDestination, .library)
    }
}
