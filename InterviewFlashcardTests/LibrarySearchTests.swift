import SwiftData
import XCTest

final class LibrarySearchTests: XCTestCase {
    @MainActor
    func testResultsMatchQuestionOrTopicAndExcludeTrashedCards() throws {
        let context = try TestModelContainer.make().mainContext
        let backend = TopicRecord(
            id: UUID(uuidString: "81000000-0000-0000-0000-000000000001")!,
            name: "后端系统"
        )
        let mobile = TopicRecord(
            id: UUID(uuidString: "81000000-0000-0000-0000-000000000002")!,
            name: "移动端"
        )
        context.insert(backend)
        context.insert(mobile)

        let first = makeCard(
            id: UUID(uuidString: "82000000-0000-0000-0000-000000000001")!,
            question: "如何设计缓存失效？",
            topic: backend,
            createdAt: Fixtures.now.addingTimeInterval(-20),
            context: context
        )
        let second = makeCard(
            id: UUID(uuidString: "82000000-0000-0000-0000-000000000002")!,
            question: "如何处理列表性能？",
            topic: mobile,
            createdAt: Fixtures.now,
            context: context
        )
        let trashed = makeCard(
            id: UUID(uuidString: "82000000-0000-0000-0000-000000000003")!,
            question: "缓存失效的旧题目",
            topic: backend,
            createdAt: Fixtures.now.addingTimeInterval(-10),
            context: context
        )
        trashed.trashedAt = Fixtures.now
        try context.save()

        XCTAssertEqual(LibrarySearch.results(from: [first, second, trashed], query: "缓存").map(\.id), [first.id])
        XCTAssertEqual(LibrarySearch.results(from: [first, second, trashed], query: "移动").map(\.id), [second.id])
        XCTAssertEqual(LibrarySearch.results(from: [first, second, trashed], query: "").map(\.id), [first.id, second.id])
    }

    @MainActor
    private func makeCard(
        id: UUID,
        question: String,
        topic: TopicRecord,
        createdAt: Date,
        context: ModelContext
    ) -> QuestionCardRecord {
        let source = SourceDocumentRecord(
            id: UUID(),
            fileName: "library-search.md",
            contentHash: id.uuidString,
            importerVersion: "test",
            importedAt: createdAt
        )
        let card = QuestionCardRecord(
            id: id,
            questionText: question,
            sourceAnchor: "library-search.md#\(id.uuidString)",
            createdAt: createdAt,
            updatedAt: createdAt,
            activatedAt: createdAt,
            topic: topic,
            sourceDocument: source
        )
        context.insert(source)
        context.insert(card)
        return card
    }
}
