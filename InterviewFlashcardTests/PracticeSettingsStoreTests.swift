import XCTest
@testable import InterviewFlashcardCore

final class PracticeSettingsStoreTests: XCTestCase {
    func testBulkSelectionSelectsAllWhenOnlySomeTopicsAreSelected() {
        let firstID = UUID()
        let secondID = UUID()
        let validTopicIDs: Set<UUID> = [firstID, secondID]

        XCTAssertEqual(
            PracticeTopicSelection.buttonTitle(
                selectedTopicIDs: [firstID],
                validTopicIDs: validTopicIDs
            ),
            "全选"
        )
        XCTAssertEqual(
            PracticeTopicSelection.toggledSelection(
                selectedTopicIDs: [firstID],
                validTopicIDs: validTopicIDs
            ),
            validTopicIDs
        )
    }

    func testBulkSelectionClearsAllWhenEveryTopicIsSelected() {
        let validTopicIDs: Set<UUID> = [UUID(), UUID()]

        XCTAssertEqual(
            PracticeTopicSelection.buttonTitle(
                selectedTopicIDs: validTopicIDs,
                validTopicIDs: validTopicIDs
            ),
            "全不选"
        )
        XCTAssertEqual(
            PracticeTopicSelection.toggledSelection(
                selectedTopicIDs: validTopicIDs,
                validTopicIDs: validTopicIDs
            ),
            []
        )
    }

    private let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let newID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!

    func testFirstUseResolvesToAllCurrentTopicsWithoutBecomingExplicit() {
        let store = InMemoryPracticeSettingsStore()

        let snapshot = store.reconcile(validTopicIDs: [firstID, secondID])

        XCTAssertNil(snapshot.explicitTopicIDs)
        XCTAssertEqual(
            snapshot.resolvedTopicIDs(validTopicIDs: [firstID, secondID]),
            [firstID, secondID]
        )
        XCTAssertFalse(snapshot.includePracticed)
    }

    func testExplicitSelectionDoesNotAutoIncludeNewTopics() {
        let store = InMemoryPracticeSettingsStore(
            snapshot: PracticeSettingsSnapshot(explicitTopicIDs: [firstID])
        )

        let snapshot = store.reconcile(
            validTopicIDs: [firstID, secondID, newID]
        )

        XCTAssertEqual(snapshot.explicitTopicIDs, [firstID])
        XCTAssertEqual(
            snapshot.resolvedTopicIDs(validTopicIDs: [firstID, secondID, newID]),
            [firstID]
        )
    }

    func testExplicitEmptySelectionRoundTrips() {
        let defaults = makeUserDefaults()
        let store = UserDefaultsPracticeSettingsStore(userDefaults: defaults)
        store.save(PracticeSettingsSnapshot(
            explicitTopicIDs: [],
            includePracticed: true
        ))

        let loaded = store.load()

        XCTAssertEqual(loaded.explicitTopicIDs, [])
        XCTAssertTrue(loaded.includePracticed)
    }

    func testDeletedTopicIDsArePrunedAndPersisted() {
        let defaults = makeUserDefaults()
        let store = UserDefaultsPracticeSettingsStore(userDefaults: defaults)
        store.save(PracticeSettingsSnapshot(
            explicitTopicIDs: [firstID, secondID],
            includePracticed: false
        ))

        let reconciled = store.reconcile(validTopicIDs: [secondID])

        XCTAssertEqual(reconciled.explicitTopicIDs, [secondID])
        XCTAssertEqual(store.load().explicitTopicIDs, [secondID])
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "PracticeSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
