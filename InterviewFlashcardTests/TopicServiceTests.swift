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
