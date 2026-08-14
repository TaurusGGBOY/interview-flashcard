import SwiftData
import XCTest
#if canImport(InterviewFlashcard)
@testable import InterviewFlashcard
#endif

final class QuestionNumberingServiceTests: XCTestCase {
    @MainActor
    func testNextNumberStartsAtOneForEmptyLibrary() throws {
        let context = try makeContext()

        XCTAssertEqual(try QuestionNumberingService().nextNumber(context: context), 1)
    }

    @MainActor
    func testNextNumberUsesLargestPositiveQuestionNumber() throws {
        let context = try makeContext()
        try insertCard(number: 1, context: context)
        try insertCard(number: 2, context: context)

        XCTAssertEqual(try QuestionNumberingService().nextNumber(context: context), 3)
    }

    @MainActor
    func testDeletingEarlierNumberDoesNotMakeItReusable() throws {
        let context = try makeContext()
        try insertCard(number: 1, context: context)
        let second = try insertCard(number: 2, context: context)
        try insertCard(number: 3, context: context)
        try context.save()

        context.delete(second)
        try context.save()

        XCTAssertEqual(try QuestionNumberingService().nextNumber(context: context), 4)
    }

    @MainActor
    func testBackfillUsesCreationDateThenUUIDAndPreservesExistingNumbers() throws {
        let context = try makeContext()
        let existing = try insertCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            number: 7,
            createdAt: Date(timeIntervalSince1970: 300),
            context: context
        )
        let first = try insertCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: Date(timeIntervalSince1970: 100),
            context: context
        )
        let second = try insertCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            createdAt: Date(timeIntervalSince1970: 100),
            context: context
        )
        let third = try insertCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 200),
            context: context
        )

        try QuestionNumberingService().backfillIfNeeded(context: context)

        XCTAssertEqual(existing.questionNumber, 7)
        XCTAssertEqual(first.questionNumber, 8)
        XCTAssertEqual(second.questionNumber, 9)
        XCTAssertEqual(third.questionNumber, 10)
    }

    @MainActor
    func testBackfillIsIdempotent() throws {
        let context = try makeContext()
        let first = try insertCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 100),
            context: context
        )
        let second = try insertCard(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: Date(timeIntervalSince1970: 200),
            context: context
        )
        let service = QuestionNumberingService()

        try service.backfillIfNeeded(context: context)
        let assignedNumbers = [first.questionNumber, second.questionNumber]
        try service.backfillIfNeeded(context: context)

        XCTAssertEqual([first.questionNumber, second.questionNumber], assignedNumbers)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        return context
    }

    @MainActor
    @discardableResult
    private func insertCard(
        id: UUID = UUID(),
        number: Int? = nil,
        createdAt: Date = Fixtures.now,
        context: ModelContext
    ) throws -> QuestionCardRecord {
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>())
                .first(where: { $0.systemKind == .others })
        )
        let source = SourceDocumentRecord(
            fileName: "\(id.uuidString).md",
            contentHash: id.uuidString,
            importerVersion: "numbering-test",
            importedAt: createdAt
        )
        let card = QuestionCardRecord(
            id: id,
            questionNumber: number,
            questionText: "Question \(id.uuidString)",
            sourceAnchor: "\(id.uuidString).md#question",
            createdAt: createdAt,
            updatedAt: createdAt,
            activatedAt: createdAt,
            topic: others,
            sourceDocument: source
        )
        context.insert(source)
        context.insert(card)
        return card
    }
}
