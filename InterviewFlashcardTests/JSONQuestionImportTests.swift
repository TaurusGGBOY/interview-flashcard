import Foundation
import SwiftData
import XCTest

final class JSONQuestionImportTests: XCTestCase {
    func testParserAcceptsStrictVersionOneContractAndNormalizesValues() throws {
        let data = Data(
            """
            {
              "formatVersion": 1,
              "questions": [
                {
                  "question": "  Redis 为什么快？  ",
                  "topic": "  Redis  ",
                  "answer": "  ## 结论\\n\\nRedis 将热点数据保存在内存中。  "
                }
              ]
            }
            """.utf8
        )

        let draft = try JSONQuestionImportParser.parse(data: data, fileName: "redis.json")

        XCTAssertEqual(draft.fileName, "redis.json")
        XCTAssertEqual(draft.items.count, 1)
        XCTAssertEqual(draft.items[0].sourceIndex, 0)
        XCTAssertEqual(draft.items[0].question, "Redis 为什么快？")
        XCTAssertEqual(draft.items[0].topicName, "Redis")
        XCTAssertEqual(draft.items[0].answer, "## 结论\n\nRedis 将热点数据保存在内存中。")
        XCTAssertEqual(draft.items[0].sourceAnchor, "questions[0]")
        XCTAssertFalse(draft.contentHash.isEmpty)
    }

    func testParserRejectsMalformedJSON() {
        assertIssues(
            data: Data(#"{"formatVersion":1,"questions":[}"#.utf8),
            expectedPaths: ["$"]
        )
    }

    func testParserRejectsUnsupportedMissingAndNonIntegerVersions() {
        assertIssues(
            json: #"{"questions":[]}"#,
            expectedPaths: ["$.formatVersion", "$.questions"]
        )
        assertIssues(
            json: #"{"formatVersion":2,"questions":[]}"#,
            expectedPaths: ["$.formatVersion", "$.questions"]
        )
        assertIssues(
            json: #"{"formatVersion":"1","questions":[]}"#,
            expectedPaths: ["$.formatVersion", "$.questions"]
        )
    }

    func testParserRejectsUnknownTopLevelAndItemFields() {
        assertIssues(
            json: """
            {
              "formatVersion": 1,
              "name": "extra",
              "questions": [
                {"question": "Q", "topic": "T", "answer": "A", "difficulty": 3}
              ]
            }
            """,
            expectedPaths: ["$.name", "$.questions[0].difficulty"]
        )
    }

    func testParserAccumulatesMissingWrongTypeAndWhitespaceIssuesInStableOrder() {
        assertIssues(
            json: """
            {
              "formatVersion": 1,
              "questions": [
                {"question": "   ", "topic": 42},
                "not-an-object",
                {"question": "Q", "topic": "T", "answer": false}
              ]
            }
            """,
            expectedPaths: [
                "$.questions[0].answer",
                "$.questions[0].question",
                "$.questions[0].topic",
                "$.questions[1]",
                "$.questions[2].answer",
            ]
        )
    }

    func testParserRejectsEmptyQuestionsArrayAndNonArrayQuestions() {
        assertIssues(
            json: #"{"formatVersion":1,"questions":[]}"#,
            expectedPaths: ["$.questions"]
        )
        assertIssues(
            json: #"{"formatVersion":1,"questions":{}}"#,
            expectedPaths: ["$.questions"]
        )
    }

    @MainActor
    func testConfirmReusesAndCreatesTopicsWhilePreservingOrderDuplicatesAndAnswers() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let existing = try TopicService().create(name: "Redis", context: context, now: Fixtures.now)
        let defaultsName = "JSONQuestionImportTests.numbering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let service = JSONQuestionImportService(
            numberingService: QuestionNumberingService(defaults: defaults),
            now: { Fixtures.now }
        )
        let draft = JSONQuestionImportDraft(
            fileName: "questions.json",
            contentHash: "json-hash",
            items: [
                .init(sourceIndex: 0, question: "Redis Q", topicName: "REDIS", answer: "Redis A"),
                .init(sourceIndex: 1, question: "重复题", topicName: "System Design", answer: "答案一"),
                .init(sourceIndex: 2, question: "重复题", topicName: "systemdesign", answer: "答案二"),
            ]
        )

        let run = try service.confirm(draft: draft, context: context)

        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
            .sorted { ($0.questionNumber ?? 0) < ($1.questionNumber ?? 0) }
        let answers = try context.fetch(FetchDescriptor<ReferenceAnswerVersionRecord>())
        XCTAssertEqual(run.status, .active)
        XCTAssertTrue(run.chunks.isEmpty)
        XCTAssertEqual(run.sourceDocument.fileName, "questions.json")
        XCTAssertEqual(run.sourceDocument.contentHash, "json-hash")
        XCTAssertEqual(run.sourceDocument.importerVersion, "json-v1")
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards.map(\.questionNumber), [1, 2, 3])
        XCTAssertEqual(cards.map(\.questionText), ["Redis Q", "重复题", "重复题"])
        XCTAssertEqual(cards.map(\.sourceAnchor), ["questions[0]", "questions[1]", "questions[2]"])
        XCTAssertEqual(cards[0].topic.id, existing.id)
        XCTAssertEqual(cards[1].topic.id, cards[2].topic.id)
        XCTAssertEqual(cards[1].topic.name, "System Design")
        XCTAssertEqual(topics.filter { TopicNameNormalization.key($0.name) == "systemdesign" }.count, 1)
        XCTAssertEqual(answers.count, 3)
        XCTAssertTrue(answers.allSatisfy { $0.version == 1 && $0.origin == .jsonImported })
        XCTAssertEqual(
            cards.map { $0.referenceAnswers.first?.answerText },
            ["Redis A", "答案一", "答案二"]
        )
    }

    @MainActor
    func testConfirmRollsBackEveryInsertedRecordWhenSaveFails() throws {
        enum ExpectedFailure: Error { case save }

        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let baselineTopicCount = try context.fetchCount(FetchDescriptor<TopicRecord>())
        let service = JSONQuestionImportService(
            now: { Fixtures.now },
            save: { _ in throw ExpectedFailure.save }
        )
        let draft = JSONQuestionImportDraft(
            fileName: "rollback.json",
            contentHash: "rollback-hash",
            items: [
                .init(sourceIndex: 0, question: "Q", topicName: "New Topic", answer: "A"),
            ]
        )

        XCTAssertThrowsError(try service.confirm(draft: draft, context: context))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TopicRecord>()), baselineTopicCount)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocumentRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ImportRunRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuestionCardRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReferenceAnswerVersionRecord>()), 0)
    }

    @MainActor
    func testBatchConfirmCreatesSeparateSourceRecordsAndConsecutiveQuestionNumbers() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        try AppModelContainer.bootstrapOthers(context: context, now: Fixtures.now)
        let defaultsName = "JSONQuestionImportTests.batch-numbering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let service = JSONQuestionImportService(
            numberingService: QuestionNumberingService(defaults: defaults),
            now: { Fixtures.now }
        )
        let drafts = [
            JSONQuestionImportDraft(
                fileName: "go.json",
                contentHash: "go-hash",
                items: [.init(sourceIndex: 0, question: "Go Q", topicName: "Go", answer: "Go A")]
            ),
            JSONQuestionImportDraft(
                fileName: "java.json",
                contentHash: "java-hash",
                items: [.init(sourceIndex: 0, question: "Java Q", topicName: "Java", answer: "Java A")]
            ),
        ]

        let runs = try service.confirm(drafts: drafts, context: context)

        XCTAssertEqual(runs.map(\.sourceDocument.fileName), ["go.json", "java.json"])
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
            .sorted { ($0.questionNumber ?? 0) < ($1.questionNumber ?? 0) }
        XCTAssertEqual(cards.map(\.questionNumber), [1, 2])
        XCTAssertEqual(cards.map(\.questionText), ["Go Q", "Java Q"])
        XCTAssertEqual(Set(cards.map { $0.sourceDocument.fileName }), ["go.json", "java.json"])
    }

    private func assertIssues(json: String, expectedPaths: [String]) {
        assertIssues(data: Data(json.utf8), expectedPaths: expectedPaths)
    }

    private func assertIssues(data: Data, expectedPaths: [String]) {
        XCTAssertThrowsError(
            try JSONQuestionImportParser.parse(data: data, fileName: "invalid.json")
        ) { error in
            guard let validation = error as? JSONQuestionImportValidationError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(validation.issues.map(\.path), expectedPaths)
            XCTAssertTrue(validation.issues.allSatisfy { !$0.message.isEmpty })
        }
    }
}
