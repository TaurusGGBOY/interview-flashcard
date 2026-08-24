import CryptoKit
import Foundation
import SwiftData

struct JSONQuestionImportItem: Identifiable, Equatable, Sendable {
    var id: Int { sourceIndex }

    let sourceIndex: Int
    let question: String
    let topicName: String
    let answer: String

    var sourceAnchor: String { "questions[\(sourceIndex)]" }
}

struct JSONQuestionImportDraft: Equatable, Sendable {
    let fileName: String
    let contentHash: String
    let items: [JSONQuestionImportItem]
}

struct JSONQuestionImportIssue: Equatable, Sendable {
    let path: String
    let message: String
}

struct JSONQuestionImportValidationError: LocalizedError, Equatable, Sendable {
    let issues: [JSONQuestionImportIssue]

    var errorDescription: String? {
        issues.map { "\($0.path)：\($0.message)" }.joined(separator: "\n")
    }
}

enum JSONQuestionImportParser {
    private static let rootKeys: Set<String> = ["formatVersion", "questions"]
    private static let itemKeys: Set<String> = ["question", "topic", "answer"]

    static func parse(data: Data, fileName: String) throws -> JSONQuestionImportDraft {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JSONQuestionImportValidationError(
                issues: [.init(path: "$", message: "不是有效的 JSON 文件。")]
            )
        }

        guard let root = object as? [String: Any] else {
            throw JSONQuestionImportValidationError(
                issues: [.init(path: "$", message: "顶层必须是对象。")]
            )
        }

        var issues: [JSONQuestionImportIssue] = []
        for key in root.keys.filter({ !rootKeys.contains($0) }).sorted() {
            issues.append(.init(path: "$.\(key)", message: "不支持此字段。"))
        }

        if !isSupportedVersion(root["formatVersion"]) {
            issues.append(.init(path: "$.formatVersion", message: "必须是整数 1。"))
        }

        var items: [JSONQuestionImportItem] = []
        if let questions = root["questions"] as? [Any] {
            if questions.isEmpty {
                issues.append(.init(path: "$.questions", message: "至少需要一道题目。"))
            } else {
                for (index, value) in questions.enumerated() {
                    parseItem(value, index: index, issues: &issues, items: &items)
                }
            }
        } else {
            issues.append(.init(path: "$.questions", message: "必须是非空数组。"))
        }

        guard issues.isEmpty else {
            throw JSONQuestionImportValidationError(issues: issues)
        }

        let hash = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return JSONQuestionImportDraft(
            fileName: fileName,
            contentHash: hash,
            items: items
        )
    }

    private static func parseItem(
        _ value: Any,
        index: Int,
        issues: inout [JSONQuestionImportIssue],
        items: inout [JSONQuestionImportItem]
    ) {
        let itemPath = "$.questions[\(index)]"
        guard let object = value as? [String: Any] else {
            issues.append(.init(path: itemPath, message: "每道题必须是对象。"))
            return
        }

        for key in object.keys.filter({ !itemKeys.contains($0) }).sorted() {
            issues.append(.init(path: "\(itemPath).\(key)", message: "不支持此字段。"))
        }

        let issueCountBeforeFields = issues.count
        let answer = requiredText(object["answer"], path: "\(itemPath).answer", issues: &issues)
        let question = requiredText(object["question"], path: "\(itemPath).question", issues: &issues)
        let topic = requiredTopic(object["topic"], path: "\(itemPath).topic", issues: &issues)

        guard issues.count == issueCountBeforeFields,
              let answer,
              let question,
              let topic else {
            return
        }

        items.append(
            JSONQuestionImportItem(
                sourceIndex: index,
                question: question,
                topicName: topic,
                answer: answer
            )
        )
    }

    private static func requiredText(
        _ value: Any?,
        path: String,
        issues: inout [JSONQuestionImportIssue]
    ) -> String? {
        guard let text = value as? String else {
            issues.append(.init(path: path, message: "必须是非空字符串。"))
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            issues.append(.init(path: path, message: "不能为空。"))
            return nil
        }
        return trimmed
    }

    private static func requiredTopic(
        _ value: Any?,
        path: String,
        issues: inout [JSONQuestionImportIssue]
    ) -> String? {
        guard let text = requiredText(value, path: path, issues: &issues) else {
            return nil
        }
        let cleaned = TopicNameNormalization.cleanedForStorage(text)
        guard !cleaned.isEmpty else {
            issues.append(.init(path: path, message: "不能为空。"))
            return nil
        }
        return cleaned
    }

    private static func isSupportedVersion(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return false
        }
        return number.doubleValue == 1 && number.intValue == 1
    }
}

@MainActor
struct JSONQuestionImportService {
    typealias Save = (ModelContext) throws -> Void

    private let numberingService: QuestionNumberingService
    private let now: @Sendable () -> Date
    private let diagnosticExporter: DiagnosticStateExporter?
    private let save: Save

    init(
        numberingService: QuestionNumberingService = QuestionNumberingService(),
        now: @escaping @Sendable () -> Date = Date.init,
        diagnosticExporter: DiagnosticStateExporter? = nil,
        save: @escaping Save = { try $0.save() }
    ) {
        self.numberingService = numberingService
        self.now = now
        self.diagnosticExporter = diagnosticExporter
        self.save = save
    }

    @discardableResult
    func confirm(
        draft: JSONQuestionImportDraft,
        context: ModelContext
    ) throws -> ImportRunRecord {
        try confirm(drafts: [draft], context: context)[0]
    }

    @discardableResult
    func confirm(
        drafts: [JSONQuestionImportDraft],
        context: ModelContext
    ) throws -> [ImportRunRecord] {
        guard !drafts.isEmpty else { return [] }

        let existingTopics = try context.fetch(FetchDescriptor<TopicRecord>())
        var topicsByKey: [String: TopicRecord] = [:]
        for topic in existingTopics.sorted(by: Self.stableTopicOrder) {
            let key = TopicNameNormalization.key(topic.name)
            if topicsByKey[key] == nil {
                topicsByKey[key] = topic
            }
        }

        let timestamp = now()
        do {
            var nextQuestionNumber = try numberingService.nextNumber(context: context)
            var runs: [ImportRunRecord] = []

            for draft in drafts {
                for item in draft.items {
                    let key = TopicNameNormalization.key(item.topicName)
                    guard topicsByKey[key] == nil else { continue }
                    let topic = TopicRecord(
                        name: item.topicName,
                        createdAt: timestamp,
                        updatedAt: timestamp
                    )
                    context.insert(topic)
                    topicsByKey[key] = topic
                }

                let source = SourceDocumentRecord(
                    fileName: draft.fileName,
                    contentHash: draft.contentHash,
                    importerVersion: "json-v1",
                    importedAt: timestamp
                )
                let run = ImportRunRecord(
                    status: .active,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    sourceDocument: source
                )
                context.insert(source)
                context.insert(run)
                runs.append(run)

                for item in draft.items {
                    let topicKey = TopicNameNormalization.key(item.topicName)
                    guard let topic = topicsByKey[topicKey] else {
                        preconditionFailure("Validated JSON Topic must resolve before persistence.")
                    }
                    let card = QuestionCardRecord(
                        questionNumber: nextQuestionNumber,
                        questionText: item.question,
                        sourceAnchor: item.sourceAnchor,
                        createdAt: timestamp,
                        updatedAt: timestamp,
                        activatedAt: timestamp,
                        topic: topic,
                        sourceDocument: source
                    )
                    let answer = ReferenceAnswerVersionRecord(
                        version: 1,
                        answerText: item.answer,
                        origin: .jsonImported,
                        createdAt: timestamp,
                        question: card
                    )
                    context.insert(card)
                    context.insert(answer)
                    nextQuestionNumber += 1
                }
            }

            try save(context)
            try? diagnosticExporter?.export(from: context)
            return runs
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func stableTopicOrder(_ lhs: TopicRecord, _ rhs: TopicRecord) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }
}
