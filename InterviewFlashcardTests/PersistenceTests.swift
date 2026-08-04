import Foundation
import SwiftData
import XCTest
@testable import InterviewFlashcard

final class PersistenceTests: XCTestCase {
    @MainActor
    func testBootstrapCreatesExactlyOneImmutableOthers() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(topics.first?.id, TopicRecord.othersID)
        XCTAssertEqual(topics.first?.name, "Others")
        XCTAssertEqual(topics.first?.systemKind, .others)
    }

    func testRubricComputesWeightedTotalLocally() {
        let scores = DimensionScores(
            correctness: 80,
            coverage: 60,
            reasoning: 80,
            structure: 80,
            tradeoffs: 70,
            precision: 100
        )
        XCTAssertEqual(ScoringRubric.general.total(for: scores), 75)
        XCTAssertEqual(ScoringRubric.general.weights.values.reduce(0, +), 100)
    }

    @MainActor
    func testSoftDeleteKeepsQuestionHistory() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let answer = try XCTUnwrap(card.referenceAnswers.first)
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: card.questionText,
            referenceAnswerTextSnapshot: answer.answerText,
            referenceAnswerVersion: answer.version,
            rawText: "值语义意味着复制后互不影响。",
            inputMode: .typed,
            startedAt: Fixtures.now.addingTimeInterval(-30),
            submittedAt: Fixtures.now,
            question: card
        )
        context.insert(attempt)
        card.trashedAt = Fixtures.now
        try context.save()

        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let attempts = try context.fetch(FetchDescriptor<AnswerAttemptRecord>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.question.id, card.id)
    }

    @MainActor
    func testDiagnosticsFetchesPersistedStateWithoutSecretFields() throws {
        let context = try TestModelContainer.make().mainContext
        _ = try Fixtures.makeCard(context: context)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.json")
        let exporter = DiagnosticStateExporter(isEnabled: true, destinationURL: destination)

        try exporter.export(from: context)

        let data = try Data(contentsOf: destination)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"schemaVersion\""))
        XCTAssertTrue(text.contains("\"systemKind\" : \"others\""))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("authorization"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("apiKey"))
    }

    #if DEBUG
    @MainActor
    func testAcceptanceSeederRefusesNonEmptyStore() throws {
        let context = try TestModelContainer.make().mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        _ = try Fixtures.makeCard(context: context)

        XCTAssertThrowsError(try AcceptanceSeeder.seed(named: "empty", context: context)) { error in
            XCTAssertEqual(error as? AcceptanceSeeder.SeedError, .storeIsNotEmpty)
        }
    }
    #endif
}
