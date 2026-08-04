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
    ]

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
        context.insert(source)

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
        context: ModelContext
    ) -> QuestionCardRecord {
        let card = QuestionCardRecord(
            id: stableUUID(namespace: 3, ordinal: ordinal),
            questionText: "验收题目 \(ordinal)：请解释该技术概念。",
            sourceAnchor: "acceptance-fixture.md#question-\(ordinal)",
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
                answerText: "验收题目 \(ordinal) 的满分答案。",
                keyPointsJSON: "[\"核心定义\",\"适用边界\"]",
                promptVersion: "acceptance-v1",
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
