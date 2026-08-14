import SwiftData
import XCTest
@testable import InterviewFlashcard

final class TopicServiceTests: XCTestCase {
    @MainActor
    func testTopicNamesAreTrimmedUniqueAndOthersCannotBeDeleted() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()

        XCTAssertThrowsError(try service.create(name: "  \n  ", context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .emptyName)
        }

        let java = try service.create(name: "  Java  ", context: context, now: Fixtures.now)
        XCTAssertEqual(java.name, "Java")

        XCTAssertThrowsError(try service.create(name: "java", context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .duplicateName("java"))
        }

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        let others = try XCTUnwrap(topics.first(where: { $0.systemKind == .others }))
        XCTAssertThrowsError(try service.delete(others, moveCardsTo: java, context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .systemTopicIsImmutable)
        }
    }

    @MainActor
    func testNamesAreDiacriticInsensitiveAndRenameIsValidated() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()
        let resume = try service.create(name: "Résumé", context: context)
        let swift = try service.create(name: "Swift", context: context)

        XCTAssertThrowsError(try service.rename(swift, to: "  resume  ", context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .duplicateName("resume"))
        }
        try service.rename(resume, to: "  JVM  ", context: context, now: Fixtures.now)
        XCTAssertEqual(resume.name, "JVM")

        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )
        XCTAssertThrowsError(try service.rename(others, to: "Other", context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .systemTopicIsImmutable)
        }
    }

    @MainActor
    func testDeletingNormalTopicMovesEveryCardBeforeDeletingIt() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let service = TopicService()
        let source = try service.create(name: "Java", context: context, now: Fixtures.now)
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )
        card.topic = source
        try context.save()
        let cardID = card.id
        let sourceID = source.id

        try service.delete(source, moveCardsTo: others, context: context, now: Fixtures.now)

        let remainingTopics = try context.fetch(FetchDescriptor<TopicRecord>())
        XCTAssertFalse(remainingTopics.contains(where: { $0.id == sourceID }))
        let cards = try context.fetch(
            FetchDescriptor<QuestionCardRecord>(
                predicate: #Predicate { candidate in
                    candidate.id == cardID
                }
            )
        )
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.topic.id, TopicRecord.othersID)
    }

    @MainActor
    func testDeletionDestinationMustExistAndDifferFromSource() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()
        let java = try service.create(name: "Java", context: context)

        XCTAssertThrowsError(try service.delete(java, moveCardsTo: java, context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .destinationMustDiffer)
        }

        let detachedDestination = TopicRecord(name: "Detached")
        XCTAssertThrowsError(try service.delete(java, moveCardsTo: detachedDestination, context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .destinationNotFound)
        }
    }

    @MainActor
    func testPermanentDeleteRemovesTopicGraphAndCleansUpAudio() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let topic = try TopicService().create(name: "Kubernetes", context: context, now: Fixtures.now)
        let source = SourceDocumentRecord(
            fileName: "kubernetes.md",
            contentHash: "kubernetes",
            importerVersion: "test",
            importedAt: Fixtures.now
        )
        let firstCard = QuestionCardRecord(
            questionText: "Pod 是什么？",
            sourceAnchor: "kubernetes.md#pod",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now,
            activatedAt: Fixtures.now,
            topic: topic,
            sourceDocument: source
        )
        let secondCard = QuestionCardRecord(
            questionText: "Service 是什么？",
            sourceAnchor: "kubernetes.md#service",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now,
            activatedAt: Fixtures.now,
            topic: topic,
            sourceDocument: source
        )
        let firstAttempt = AnswerAttemptRecord(
            questionTextSnapshot: firstCard.questionText,
            referenceAnswerTextSnapshot: "Pod 是最小调度单元。",
            referenceAnswerVersion: 1,
            rawText: "回答一",
            inputMode: .voice,
            startedAt: Fixtures.now,
            submittedAt: Fixtures.now,
            question: firstCard
        )
        let secondAttempt = AnswerAttemptRecord(
            questionTextSnapshot: secondCard.questionText,
            referenceAnswerTextSnapshot: "Service 提供稳定访问入口。",
            referenceAnswerVersion: 1,
            rawText: "回答二",
            inputMode: .typed,
            startedAt: Fixtures.now,
            submittedAt: Fixtures.now,
            question: secondCard
        )
        let evaluation = EvaluationRecord(
            totalScore: 80,
            scores: DimensionScores(
                correctness: 80,
                coverage: 80,
                reasoning: 80,
                structure: 80,
                tradeoffs: 80,
                precision: 80
            ),
            confidence: "high",
            provider: "fixture",
            modelID: "fixture",
            promptVersion: "fixture",
            rubricVersion: "fixture",
            createdAt: Fixtures.now,
            attempt: firstAttempt
        )
        let audio = AudioAssetRecord(
            relativePath: "audio/topic-answer.m4a",
            duration: 1,
            byteCount: 1,
            checksum: "fixture",
            transcriptionEngine: "fixture",
            localeIdentifier: "zh-CN",
            attempt: firstAttempt
        )
        context.insert(source)
        context.insert(firstCard)
        context.insert(secondCard)
        context.insert(firstAttempt)
        context.insert(secondAttempt)
        context.insert(evaluation)
        context.insert(audio)
        try context.save()

        let removed = TopicRemovedAudioBox()
        let service = TopicService(removeAudio: { removed.paths.append($0) })
        let impact = try service.deletionImpact(for: topic, context: context)

        XCTAssertEqual(
            impact,
            TopicService.TopicDeletionImpact(
                topicID: topic.id,
                questionCount: 2,
                answerCount: 2,
                evaluationCount: 1,
                audioCount: 1
            )
        )

        try service.permanentlyDelete(topic: topic, context: context)

        XCTAssertFalse(try context.fetch(FetchDescriptor<TopicRecord>()).contains { $0.id == topic.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<QuestionCardRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AnswerAttemptRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<EvaluationRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AudioAssetRecord>()).isEmpty)
        XCTAssertEqual(removed.paths, ["audio/topic-answer.m4a"])
    }

    @MainActor
    func testPermanentDeleteRejectsOthers() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )
        let service = TopicService(removeAudio: { _ in })

        XCTAssertThrowsError(try service.deletionImpact(for: others, context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .systemTopicIsImmutable)
        }
        XCTAssertThrowsError(try service.permanentlyDelete(topic: others, context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .systemTopicIsImmutable)
        }
    }

    @MainActor
    func testLibraryOrderingAlwaysPlacesOthersFirst() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()
        _ = try service.create(name: "Swift", context: context)
        _ = try service.create(name: "Java", context: context)

        let ordered = try context.fetch(FetchDescriptor<TopicRecord>())
            .sorted(by: TopicService.libraryOrder)

        XCTAssertEqual(ordered.map(\.name), ["Others", "Java", "Swift"])
        XCTAssertEqual(ordered.first?.systemKind, .others)
    }
}

private final class TopicRemovedAudioBox: @unchecked Sendable {
    var paths: [String] = []
}
