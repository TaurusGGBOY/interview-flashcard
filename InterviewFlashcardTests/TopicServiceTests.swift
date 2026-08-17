import SwiftData
import XCTest

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
    func testCreateCleansInvisibleSpacingAndDeduplicatesNormalizedNames() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()

        // U+2006 is invisible; the stored name must be clean and visible.
        let mysql = try service.create(
            name: "m\u{2006}y\u{2006}s\u{2006}q\u{2006}l",
            context: context,
            now: Fixtures.now
        )
        XCTAssertEqual(mysql.name, "mysql")

        // Invisible spacing collapses; the generic fallback joins the letters.
        let systemDesign = try service.create(
            name: "system\u{2006}design",
            context: context,
            now: Fixtures.now
        )
        XCTAssertEqual(systemDesign.name, "systemdesign")

        // A normal-space duplicate of an invisible-spacing name is rejected.
        XCTAssertThrowsError(try service.create(name: "system design", context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .duplicateName("system design"))
        }
        XCTAssertThrowsError(try service.create(name: "SystemDesign", context: context)) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .duplicateName("SystemDesign"))
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
    func testMoveCardsToTopicUpdatesEverySelectedCard() throws {
        let context = try TestModelContainer.make().mainContext
        let firstCard = try Fixtures.makeCard(context: context)
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )
        let destination = try TopicService().create(
            name: "分布式系统",
            context: context,
            now: Fixtures.now
        )
        let secondSource = SourceDocumentRecord(
            id: UUID(),
            fileName: "fixture-batch.md",
            contentHash: "fixture-batch",
            importerVersion: "test",
            importedAt: Fixtures.now
        )
        let secondCard = QuestionCardRecord(
            id: UUID(),
            questionText: "如何保证消息至少一次投递时的幂等性？",
            sourceAnchor: "fixture-batch.md#idempotency",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now,
            activatedAt: Fixtures.now,
            topic: others,
            sourceDocument: secondSource
        )
        context.insert(secondSource)
        context.insert(secondCard)
        try context.save()

        let updatedAt = Fixtures.now.addingTimeInterval(60)
        try TopicService().moveCards(
            [firstCard, secondCard],
            to: destination,
            context: context,
            now: updatedAt
        )

        XCTAssertEqual(firstCard.topic.id, destination.id)
        XCTAssertEqual(secondCard.topic.id, destination.id)
        XCTAssertEqual(firstCard.updatedAt, updatedAt)
        XCTAssertEqual(secondCard.updatedAt, updatedAt)
    }

    @MainActor
    func testBatchDeleteMovesCardsFromEveryTopicAndLeavesSelectedTopicsOutOfDestinations() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()
        let java = try service.create(name: "Java", context: context, now: Fixtures.now)
        let swift = try service.create(name: "Swift", context: context, now: Fixtures.now)
        let destination = try service.create(name: "Backend", context: context, now: Fixtures.now)

        let firstCard = try Fixtures.makeCard(context: context)
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )
        let secondSource = SourceDocumentRecord(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            fileName: "fixture-2.md",
            contentHash: "fixture-2",
            importerVersion: "test",
            importedAt: Fixtures.now
        )
        let secondCard = QuestionCardRecord(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            questionText: "什么是引用语义？",
            sourceAnchor: "fixture-2.md#reference-semantics",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now,
            activatedAt: Fixtures.now,
            topic: others,
            sourceDocument: secondSource
        )
        context.insert(secondSource)
        context.insert(secondCard)
        firstCard.topic = java
        secondCard.topic = swift
        try context.save()

        let destinations = try service.deletionDestinations(
            for: [java, swift],
            context: context
        )
        XCTAssertEqual(destinations.map(\.id), [TopicRecord.othersID, destination.id])

        try service.delete(
            [java, swift],
            moveCardsTo: destination,
            context: context,
            now: Fixtures.now
        )

        let remainingTopics = try context.fetch(FetchDescriptor<TopicRecord>())
        XCTAssertFalse(remainingTopics.contains(where: { $0.id == java.id || $0.id == swift.id }))
        XCTAssertEqual(firstCard.topic.id, destination.id)
        XCTAssertEqual(secondCard.topic.id, destination.id)
    }

    @MainActor
    func testBatchDeleteRejectsEmptySelectionAndOthers() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let service = TopicService()
        let java = try service.create(name: "Java", context: context)
        let others = try XCTUnwrap(
            try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others })
        )

        XCTAssertThrowsError(
            try service.delete([], moveCardsTo: others, context: context)
        ) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .emptySelection)
        }

        XCTAssertThrowsError(
            try service.delete([others, java], moveCardsTo: java, context: context)
        ) { error in
            XCTAssertEqual(error as? TopicService.ServiceError, .systemTopicIsImmutable)
        }

        XCTAssertThrowsError(
            try service.deletionDestinations(for: [others], context: context)
        ) { error in
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
