import SwiftData
import XCTest

final class TopicNameHygieneTests: XCTestCase {
    @MainActor
    func testRepairRenamesPollutedTopicsAndMergesNormalizedDuplicates() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)

        // Legacy polluted records persisted before the hygiene pass existed.
        let systemDesign = TopicRecord(
            name: "system\u{2006}design",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now
        )
        let mysql = TopicRecord(
            name: "m\u{2006}y\u{2006}s\u{2006}q\u{2006}l",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now
        )
        let cleanRedis = TopicRecord(
            name: "redis",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now
        )
        let pollutedRedis = TopicRecord(
            name: "re\u{2006}di\u{2006}s",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now
        )
        for topic in [systemDesign, mysql, cleanRedis, pollutedRedis] {
            context.insert(topic)
        }
        let card = try Fixtures.makeCard(context: context)
        card.topic = pollutedRedis
        try context.save()

        try TopicNameHygiene.repair(context: context, now: Fixtures.now)

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        XCTAssertEqual(Set(topics.map(\.name)), ["Others", "system design", "mysql", "redis"])
        let survivingRedis = try XCTUnwrap(topics.first(where: { $0.name == "redis" }))
        XCTAssertEqual(survivingRedis.id, cleanRedis.id)
        XCTAssertEqual(survivingRedis.cards.map(\.id), [card.id])
        XCTAssertFalse(topics.contains(where: { $0.id == pollutedRedis.id }))
    }

    @MainActor
    func testRepairIsIdempotentAndNeverTouchesOthers() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let systemDesign = TopicRecord(
            name: "system\u{2006}design",
            createdAt: Fixtures.now,
            updatedAt: Fixtures.now
        )
        context.insert(systemDesign)
        try context.save()

        try TopicNameHygiene.repair(context: context, now: Fixtures.now)
        try TopicNameHygiene.repair(context: context, now: Fixtures.now)

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        XCTAssertEqual(Set(topics.map(\.name)), ["Others", "system design"])
        let others = try XCTUnwrap(topics.first(where: { $0.systemKind == .others }))
        XCTAssertEqual(others.name, "Others")
    }
}
