import Foundation
import SwiftData
import XCTest
@testable import InterviewFlashcard

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_787_846_400)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    @MainActor
    static func makeCard(
        context: ModelContext,
        question: String = "什么是值语义？"
    ) throws -> QuestionCardRecord {
        try AppModelContainer.bootstrapOthers(context: context, now: now)
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        let others = try XCTUnwrap(topics.first(where: { $0.systemKind == .others }))
        let source = SourceDocumentRecord(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            fileName: "fixture.md",
            contentHash: "fixture",
            importerVersion: "test",
            importedAt: now
        )
        let card = QuestionCardRecord(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            questionText: question,
            sourceAnchor: "fixture.md#value-semantics",
            createdAt: now,
            updatedAt: now,
            activatedAt: now,
            topic: others,
            sourceDocument: source
        )
        context.insert(source)
        context.insert(card)
        context.insert(
            ReferenceAnswerVersionRecord(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                version: 1,
                answerText: "复制后两个值彼此独立。",
                createdAt: now,
                question: card
            )
        )
        try context.save()
        return card
    }
}

struct FixedRandomNumberGenerator: RandomNumberGenerator {
    private var values: [UInt64]
    private var index = 0

    init(values: [UInt64]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    mutating func next() -> UInt64 {
        defer { index = (index + 1) % values.count }
        return values[index]
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
