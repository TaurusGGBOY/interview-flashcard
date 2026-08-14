import XCTest
#if canImport(InterviewFlashcard)
@testable import InterviewFlashcard
#endif

final class LibraryQuestionOrderingTests: XCTestCase {
    @MainActor
    func testNumberedQuestionsSortByNumberDescending() {
        let cards = [
            makeCard(number: 8, idSuffix: 8),
            makeCard(number: 3, idSuffix: 3),
            makeCard(number: 11, idSuffix: 11)
        ]

        XCTAssertEqual(
            cards.sorted(by: LibraryQuestionOrdering.newestFirst).compactMap(\.questionNumber),
            [11, 8, 3]
        )
    }

    @MainActor
    func testUnnumberedMigrationQuestionsUseNewestCreationDateFirst() {
        let older = makeCard(
            number: nil,
            idSuffix: 1,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeCard(
            number: nil,
            idSuffix: 2,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            [older, newer].sorted(by: LibraryQuestionOrdering.newestFirst).map(\.id),
            [newer.id, older.id]
        )
    }

    @MainActor
    func testEqualNumbersUseStableCreationDateAndUUIDFallback() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let date = Date(timeIntervalSince1970: 100)
        let second = makeCard(number: 7, id: secondID, createdAt: date)
        let first = makeCard(number: 7, id: firstID, createdAt: date)

        let expected = [firstID, secondID]
        XCTAssertEqual(
            [second, first].sorted(by: LibraryQuestionOrdering.newestFirst).map(\.id),
            expected
        )
        XCTAssertEqual(
            [first, second].sorted(by: LibraryQuestionOrdering.newestFirst).map(\.id),
            expected
        )
    }

    @MainActor
    func testNumberedQuestionsAppearBeforeUnnumberedMigrationQuestions() {
        let unnumbered = makeCard(
            number: nil,
            idSuffix: 1,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let numbered = makeCard(
            number: 1,
            idSuffix: 2,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            [unnumbered, numbered].sorted(by: LibraryQuestionOrdering.newestFirst).map(\.id),
            [numbered.id, unnumbered.id]
        )
    }

    @MainActor
    private func makeCard(
        number: Int?,
        id: UUID? = nil,
        idSuffix: Int = 0,
        createdAt: Date = Fixtures.now
    ) -> QuestionCardRecord {
        let cardID = id ?? UUID(
            uuidString: String(format: "00000000-0000-0000-0000-%012d", idSuffix)
        )!
        let topic = TopicRecord(name: "Kubernetes", createdAt: createdAt, updatedAt: createdAt)
        let source = SourceDocumentRecord(
            fileName: "ordering.md",
            contentHash: cardID.uuidString,
            importerVersion: "ordering-test",
            importedAt: createdAt
        )
        return QuestionCardRecord(
            id: cardID,
            questionNumber: number,
            questionText: "Question \(idSuffix)",
            sourceAnchor: "ordering.md#\(idSuffix)",
            createdAt: createdAt,
            updatedAt: createdAt,
            activatedAt: createdAt,
            topic: topic,
            sourceDocument: source
        )
    }
}
