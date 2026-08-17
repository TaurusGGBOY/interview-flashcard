import Foundation
import SwiftData
import XCTest

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_787_846_400)
    static let seniorReferenceAnswer = """
    ## 结论
    可靠的并发服务要先隔离共享状态，再用可观测的失败恢复流程保证结果一致；实现选择必须结合吞吐、延迟和运维成本。

    ## 核心要点
    - 通过隔离共享状态降低并发竞争，并用锁或 actor 明确访问边界。
    - 失败时使用幂等重试和补偿机制恢复，避免重复副作用。
    - 根据一致性、延迟与成本做工程取舍，并通过监控和压测验证方案。

    ## 边界与取舍
    当下游超时、重复投递或部分失败时，重试可能放大流量，因此应设置超时、退避和上限；强一致方案会牺牲部分吞吐，最终一致方案则需要处理读到旧数据的窗口。后续可以追问如何设计幂等键、如何观测恢复进度，以及怎样在容量受限时降级。
    """
    static let indentedSeniorReferenceAnswer = seniorReferenceAnswer
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "    \($0)" }
        .joined(separator: "\n")

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    @MainActor
    static func makeCard(
        context: ModelContext,
        question: String = "什么是值语义？",
        includeReferenceAnswer: Bool = true
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
        if includeReferenceAnswer {
            context.insert(
                ReferenceAnswerVersionRecord(
                    id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                    version: 1,
                    answerText: "复制后两个值彼此独立。",
                    createdAt: now,
                    question: card
                )
            )
        }
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

@MainActor
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @escaping @MainActor () async throws -> T,
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
