import Foundation
import SwiftData

#if DEBUG
enum AcceptanceSeeder {
    enum SeedError: Error, Equatable {
        case unknownFixture(String)
        case storeIsNotEmpty
    }

    static let supportedFixtures: Set<String> = [
        "empty",
        "reclassification-103",
        "practice-mixed",
        "processing",
        "history",
        "insights",
        "trash",
        "mvp-workflow",
        "real-question-demo",
    ]

    private static let syncMapReferenceAnswer = """
    ## 结论
    `sync.Map.Load` 返回的是 `(any, bool)`，示例里的 `v` 仍然是 `interface{}`（即 `any`），所以不能直接用字符串下标；先做类型断言，再访问 map 才能编译并保持失败可观测。

    ## 核心要点
    - `Load` 只负责取出接口值和存在标记，必须先检查 `ok`，再把值断言为 `map[string]string`。
    - 类型断言成功后才能执行 `typed["province"]`，断言失败应走显式错误或降级路径，不能让 panic 隐藏数据问题。
    - `sync.Map` 适合读多写少、键集合动态的场景；普通 map 加锁通常更容易维护，需要用压测比较吞吐和内存。

    ## 边界与取舍
    当键不存在、值类型不符合预期或并发写入复杂时，`Load` 可能返回 `ok == false` 或断言失败；`sync.Map` 的便利性会牺牲部分类型安全和可读性。生产代码应记录异常、限制重试并用竞态检测和基准测试验证选择，后续可追问如何封装泛型访问器。
    """

    private static let syncMapKeyPoints = "[\"Load 返回接口值和存在标记，需先检查 ok 并做类型断言。\",\"断言成功后才能通过字符串下标访问 map，失败应走显式错误路径。\",\"sync.Map 与加锁 map 的选择要结合读写比例、吞吐和内存压测。\"]"

    private static let reverseStringReferenceAnswer = """
    ## 结论
    Go 的字符串不可变，因此应先转换为可变的 `[]rune`，再用双指针从两端向中间交换，最后转换回字符串；交换过程只需一个临时变量，但 rune 切片本身仍是 O(n) 的可变副本。

    ## 核心要点
    - `[]rune` 能避免直接按字节切分多字节字符，左右指针每次交换一个完整 code point。
    - 循环只需处理 `i < len(runes)/2`，交换 `runes[i]` 与 `runes[n-1-i]` 后即可原地完成翻转。
    - 时间复杂度是 O(n)，切片本身需要 O(n) 的可变副本；若业务接受字节语义，`[]byte` 更快但不能保证 Unicode 正确。

    ## 边界与取舍
    组合字符、零宽连接符和规范化等复杂 Unicode 文本可能包含多个 code point，rune 翻转不等于按用户感知字符翻转；需要 grapheme 库时应明确增加依赖和成本。对超大字符串还要权衡复制内存与实现复杂度，后续可追问如何用 `utf8` 校验输入。
    """

    private static let reverseStringKeyPoints = "[\"使用 []rune 处理多字节字符，并通过双指针原地交换。\",\"循环边界为 i < n/2，时间复杂度 O(n)。\",\"rune 翻转不等于用户感知字符，复杂 Unicode 需要额外库和取舍。\"]"

    private static let goroutineLeakReferenceAnswer = """
    ## 结论
    并发示例里，未初始化的 channel 会让发送和接收永久阻塞，`time.Tick` 又没有停止出口，二者都可能把 goroutine 和定时器留在后台。定位泄漏要先用 pprof、goroutine dump 和指标确认持续增长的调用栈，再为每条阻塞路径设计可取消的生命周期。

    ## 核心要点
    - 给长期任务传递带取消信号的 context，并在 select 中同时监听 `ctx.Done()` 与业务 channel。
    - 发送方和接收方必须约定关闭方向，使用 `defer` 释放 ticker、连接和 worker，避免无人消费的 channel 永久阻塞。
    - 用 goroutine 数量、阻塞栈和请求关联 ID 做监控，在压测、超时和客户端断连场景验证回收速度。

    ## 边界与取舍
    无缓冲 channel、忘记关闭响应体、无限重试和后台 goroutine 都可能造成泄漏；增加缓冲只能缓解瞬时背压，不能替代取消和超时。更严格的生命周期管理会增加样板代码，但能换取可预测的资源上限，后续可追问如何在服务关闭时等待 worker 安全退出。
    """

    private static let goroutineLeakKeyPoints = "[\"用 context.Done 让任务和 channel 阻塞路径可取消。\",\"明确 channel 关闭责任并用 defer 释放 ticker、连接和 worker。\",\"通过 goroutine 指标、阻塞栈和压测验证泄漏回收速度。\"]"

    @MainActor
    static func seed(named name: String, context: ModelContext) throws {
        guard supportedFixtures.contains(name) else {
            throw SeedError.unknownFixture(name)
        }
        try verifyStoreIsEmpty(context: context)

        guard name != "empty" else {
            try context.save()
            return
        }

        let now = Date(timeIntervalSince1970: 1_787_846_400) // 2026-08-27 16:00:00 UTC
        let others = try fetchOthers(context: context)
        let backend = TopicRecord(
            id: stableUUID(namespace: 1, ordinal: 1),
            name: "后端",
            createdAt: now,
            updatedAt: now
        )
        let ios = TopicRecord(
            id: stableUUID(namespace: 1, ordinal: 2),
            name: "iOS",
            createdAt: now,
            updatedAt: now
        )
        context.insert(backend)
        context.insert(ios)

        let source = SourceDocumentRecord(
            id: stableUUID(namespace: 2, ordinal: 1),
            fileName: "acceptance-fixture.md",
            sourcePath: "Tests/Fixtures/acceptance-fixture.md",
            contentHash: "acceptance-fixture-v1",
            importerVersion: "acceptance-seeder-1",
            importedAt: now
        )
        if name != "real-question-demo" {
            context.insert(source)
        }

        switch name {
        case "reclassification-103":
            for index in 1...103 {
                _ = insertCard(
                    ordinal: index,
                    topic: others,
                    source: source,
                    now: now,
                    context: context
                )
            }
        case "practice-mixed":
            let first = insertCard(ordinal: 1, topic: backend, source: source, now: now, context: context)
            _ = insertCard(ordinal: 2, topic: backend, source: source, now: now, context: context)
            _ = insertCard(ordinal: 3, topic: ios, source: source, now: now, context: context)
            _ = insertCard(ordinal: 4, topic: ios, source: source, now: now, context: context)
            _ = insertAttempt(ordinal: 1, question: first, submittedAt: now, completed: true, context: context)
        case "processing":
            _ = insertCard(ordinal: 1, topic: backend, source: source, now: now, context: context)
        case "history":
            let card = insertCard(ordinal: 1, topic: backend, source: source, now: now, context: context)
            _ = insertAttempt(ordinal: 1, question: card, submittedAt: now.addingTimeInterval(-86_400), completed: true, context: context)
            let voiceAttempt = insertAttempt(
                ordinal: 2,
                question: card,
                submittedAt: now,
                completed: true,
                inputMode: .voice,
                context: context
            )
            context.insert(
                AudioAssetRecord(
                    relativePath: "Audio/acceptance-history.m4a",
                    duration: 3,
                    byteCount: 128,
                    checksum: "acceptance-audio",
                    transcriptionEngine: "stub",
                    localeIdentifier: "zh-CN",
                    attempt: voiceAttempt
                )
            )
            try writeFixtureAudio(relativePath: "Audio/acceptance-history.m4a")
        case "insights":
            for index in 1...4 {
                let topic = index.isMultiple(of: 2) ? ios : backend
                let card = insertCard(ordinal: index, topic: topic, source: source, now: now, context: context)
                if index <= 2 {
                    _ = insertAttempt(
                        ordinal: index,
                        question: card,
                        submittedAt: now.addingTimeInterval(-86_400),
                        completed: true,
                        context: context
                    )
                }
            }
            let firstCard = try context.fetch(FetchDescriptor<QuestionCardRecord>())
                .first(where: { $0.id == stableUUID(namespace: 3, ordinal: 1) })
            if let firstCard {
                _ = insertAttempt(
                    ordinal: 5,
                    question: firstCard,
                    submittedAt: now,
                    completed: true,
                    context: context
                )
            }
        case "trash":
            _ = insertCard(ordinal: 1, topic: backend, source: source, now: now, context: context)
            let trashed = insertCard(ordinal: 2, topic: ios, source: source, now: now, context: context)
            trashed.trashedAt = now
            _ = insertAttempt(ordinal: 1, question: trashed, submittedAt: now, completed: true, context: context)
            _ = insertAttempt(ordinal: 2, question: trashed, submittedAt: now.addingTimeInterval(60), completed: true, context: context)
        case "mvp-workflow":
            let first = insertCard(ordinal: 1, topic: backend, source: source, now: now, context: context)
            _ = insertCard(ordinal: 2, topic: ios, source: source, now: now, context: context)
            _ = insertCard(ordinal: 3, topic: others, source: source, now: now, context: context)
            _ = insertAttempt(ordinal: 1, question: first, submittedAt: now, completed: true, context: context)
        case "real-question-demo":
            let go = TopicRecord(
                id: stableUUID(namespace: 8, ordinal: 1),
                name: "Go",
                createdAt: now,
                updatedAt: now
            )
            context.insert(go)

            let syncMapSource = SourceDocumentRecord(
                id: stableUUID(namespace: 9, ordinal: 1),
                fileName: "q022.md",
                sourcePath: "go-interview/question/q022.md",
                contentHash: "real-go-q022-v1",
                importerVersion: "real-demo-seed-v1",
                importedAt: now
            )
            let reverseStringSource = SourceDocumentRecord(
                id: stableUUID(namespace: 9, ordinal: 2),
                fileName: "q003.md",
                sourcePath: "go-interview/question/q003.md",
                contentHash: "real-go-q003-v1",
                importerVersion: "real-demo-seed-v1",
                importedAt: now
            )
            let goroutineLeakSource = SourceDocumentRecord(
                id: stableUUID(namespace: 9, ordinal: 3),
                fileName: "q015.md",
                sourcePath: "go-interview/question/q015.md",
                contentHash: "real-go-q015-v1",
                importerVersion: "real-demo-seed-v1",
                importedAt: now
            )
            context.insert(syncMapSource)
            context.insert(reverseStringSource)
            context.insert(goroutineLeakSource)

            _ = insertCard(
                ordinal: 1,
                topic: go,
                source: syncMapSource,
                now: now,
                context: context,
                questionText: "sync.Map 的用法：示例代码中 v[\"province\"] 为什么会编译失败，应该如何修正？",
                answerText: Self.syncMapReferenceAnswer,
                sourceAnchor: "go-interview/question/q022.md#解析",
                keyPointsJSON: Self.syncMapKeyPoints,
                promptVersion: PromptCatalog.refineVersion
            )
            _ = insertCard(
                ordinal: 2,
                topic: go,
                source: reverseStringSource,
                now: now,
                context: context,
                questionText: "请实现一个算法，在不使用额外数据结构和存储空间的情况下，翻转给定字符串（长度不超过 5000）。",
                answerText: Self.reverseStringReferenceAnswer,
                sourceAnchor: "go-interview/question/q003.md#问题描述",
                keyPointsJSON: Self.reverseStringKeyPoints,
                promptVersion: PromptCatalog.refineVersion
            )
            _ = insertCard(
                ordinal: 3,
                topic: go,
                source: goroutineLeakSource,
                now: now,
                context: context,
                questionText: "Go 并发题：未初始化 channel 与 time.Tick 的示例会发生什么，如何避免阻塞与 goroutine 泄漏？",
                answerText: Self.goroutineLeakReferenceAnswer,
                sourceAnchor: "go-interview/question/q015.md#7-channel",
                keyPointsJSON: Self.goroutineLeakKeyPoints,
                promptVersion: PromptCatalog.refineVersion
            )
        default:
            break
        }

        try context.save()
    }

    @MainActor
    private static func verifyStoreIsEmpty(context: ModelContext) throws {
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        let onlyOthers = topics.count == 1 && topics[0].systemKind == .others
        let hasSources = try context.fetchCount(FetchDescriptor<SourceDocumentRecord>()) > 0
        let hasCards = try context.fetchCount(FetchDescriptor<QuestionCardRecord>()) > 0
        let hasAttempts = try context.fetchCount(FetchDescriptor<AnswerAttemptRecord>()) > 0
        guard onlyOthers, !hasSources, !hasCards, !hasAttempts else {
            throw SeedError.storeIsNotEmpty
        }
    }

    @MainActor
    private static func fetchOthers(context: ModelContext) throws -> TopicRecord {
        let rawKind = SystemTopicKind.others.rawValue
        let descriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { $0.systemKindRaw == rawKind }
        )
        guard let others = try context.fetch(descriptor).first else {
            throw SeedError.storeIsNotEmpty
        }
        return others
    }

    @MainActor
    @discardableResult
    private static func insertCard(
        ordinal: Int,
        topic: TopicRecord,
        source: SourceDocumentRecord,
        now: Date,
        context: ModelContext,
        questionText: String? = nil,
        answerText: String? = nil,
        sourceAnchor: String? = nil,
        keyPointsJSON: String? = nil,
        promptVersion: String? = nil
    ) -> QuestionCardRecord {
        let card = QuestionCardRecord(
            id: stableUUID(namespace: 3, ordinal: ordinal),
            questionText: questionText ?? "验收题目 \(ordinal)：请解释该技术概念。",
            sourceAnchor: sourceAnchor ?? "acceptance-fixture.md#question-\(ordinal)",
            createdAt: now,
            updatedAt: now,
            activatedAt: now,
            topic: topic,
            sourceDocument: source
        )
        context.insert(card)

        context.insert(
            ReferenceAnswerVersionRecord(
                id: stableUUID(namespace: 4, ordinal: ordinal),
                version: 1,
                answerText: answerText ?? "验收题目 \(ordinal) 的满分答案。",
                keyPointsJSON: keyPointsJSON ?? "[\"核心定义\",\"适用边界\"]",
                promptVersion: promptVersion ?? "acceptance-v1",
                createdAt: now,
                question: card
            )
        )
        return card
    }

    @MainActor
    @discardableResult
    private static func insertAttempt(
        ordinal: Int,
        question: QuestionCardRecord,
        submittedAt: Date,
        completed: Bool,
        inputMode: AnswerInputMode = .typed,
        context: ModelContext
    ) -> AnswerAttemptRecord {
        let attempt = AnswerAttemptRecord(
            id: stableUUID(namespace: 5, ordinal: ordinal),
            questionTextSnapshot: question.questionText,
            referenceAnswerTextSnapshot: question.referenceAnswers.first?.answerText ?? "满分答案",
            referenceAnswerVersion: 1,
            rawText: "这是第 \(ordinal) 次验收回答。",
            inputMode: inputMode,
            processingStatus: completed ? .completed : .saved,
            startedAt: submittedAt.addingTimeInterval(-60),
            submittedAt: submittedAt,
            question: question
        )
        context.insert(attempt)

        guard completed else { return attempt }

        let polish = PolishResultRecord(
            id: stableUUID(namespace: 6, ordinal: ordinal),
            revision: 1,
            inputText: attempt.rawText,
            polishedText: "这是第 \(ordinal) 次经过润色的验收回答。",
            promptVersion: "polish-acceptance-v1",
            modelID: "stub",
            createdAt: submittedAt,
            attempt: attempt
        )
        context.insert(polish)

        let scores = DimensionScores(
            correctness: 80,
            coverage: 60,
            reasoning: 80,
            structure: 80,
            tradeoffs: 70,
            precision: 100
        )
        context.insert(
            EvaluationRecord(
                id: stableUUID(namespace: 7, ordinal: ordinal),
                totalScore: ScoringRubric.general.total(for: scores),
                scores: scores,
                confidence: "high",
                provider: "stub",
                modelID: "stub",
                promptVersion: "evaluate-acceptance-v1",
                rubricVersion: "general-v1",
                createdAt: submittedAt,
                attempt: attempt,
                polishResultID: polish.id
            )
        )
        return attempt
    }

    private static func stableUUID(namespace: Int, ordinal: Int) -> UUID {
        let text = String(format: "%08d-0000-0000-0000-%012d", namespace, ordinal)
        return UUID(uuidString: text)!
    }

    private static func writeFixtureAudio(relativePath: String) throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InterviewFlashcard", isDirectory: true)
        let url = support.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data("fixture-audio".utf8).write(to: url, options: .atomic)
        }
    }
}
#endif
