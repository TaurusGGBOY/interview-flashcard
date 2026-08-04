import Foundation
import SwiftData

@MainActor
struct TopicService {
    enum ServiceError: LocalizedError, Equatable {
        case emptyName
        case duplicateName(String)
        case systemTopicIsImmutable
        case destinationMustDiffer
        case destinationNotFound
        case topicNotFound

        var errorDescription: String? {
            switch self {
            case .emptyName:
                "Topic 名称不能为空。"
            case let .duplicateName(name):
                "已经存在名为“\(name)”的 Topic。"
            case .systemTopicIsImmutable:
                "待分类（Others）是系统 Topic，不能重命名或删除。"
            case .destinationMustDiffer:
                "请选择另一个 Topic 接收现有题目。"
            case .destinationNotFound:
                "接收题目的 Topic 已不存在，请重新选择。"
            case .topicNotFound:
                "要修改的 Topic 已不存在。"
            }
        }
    }

    private let diagnosticExporter: DiagnosticStateExporter?

    init(diagnosticExporter: DiagnosticStateExporter? = nil) {
        self.diagnosticExporter = diagnosticExporter
    }

    @discardableResult
    func create(
        name: String,
        context: ModelContext,
        now: Date = Date()
    ) throws -> TopicRecord {
        let validatedName = try validated(name: name, excluding: nil, context: context)
        let topic = TopicRecord(name: validatedName, createdAt: now, updatedAt: now)
        context.insert(topic)
        try context.save()
        exportDiagnostics(from: context)
        return topic
    }

    func rename(
        _ topic: TopicRecord,
        to name: String,
        context: ModelContext,
        now: Date = Date()
    ) throws {
        guard topic.systemKindRaw == nil else {
            throw ServiceError.systemTopicIsImmutable
        }
        try requireExisting(topic, context: context)

        topic.name = try validated(name: name, excluding: topic.id, context: context)
        topic.updatedAt = now
        try context.save()
        exportDiagnostics(from: context)
    }

    func delete(
        _ topic: TopicRecord,
        moveCardsTo destination: TopicRecord,
        context: ModelContext,
        now: Date = Date()
    ) throws {
        guard topic.systemKindRaw == nil else {
            throw ServiceError.systemTopicIsImmutable
        }
        guard topic.id != destination.id else {
            throw ServiceError.destinationMustDiffer
        }
        try requireExisting(topic, context: context)

        let destinationID = destination.id
        let destinationDescriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { candidate in
                candidate.id == destinationID
            }
        )
        guard let persistedDestination = try context.fetch(destinationDescriptor).first else {
            throw ServiceError.destinationNotFound
        }

        for card in Array(topic.cards) {
            card.topic = persistedDestination
            card.updatedAt = now
        }
        context.delete(topic)
        try context.save()
        exportDiagnostics(from: context)
    }

    func deletionDestinations(
        for topic: TopicRecord,
        context: ModelContext
    ) throws -> [TopicRecord] {
        try context.fetch(FetchDescriptor<TopicRecord>())
            .filter { $0.id != topic.id }
            .sorted(by: Self.libraryOrder)
    }

    static func libraryOrder(_ lhs: TopicRecord, _ rhs: TopicRecord) -> Bool {
        if lhs.systemKind == .others { return rhs.systemKind != .others }
        if rhs.systemKind == .others { return false }

        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison == .orderedSame {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return comparison == .orderedAscending
    }

    private func validated(
        name: String,
        excluding excludedID: UUID?,
        context: ModelContext
    ) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ServiceError.emptyName
        }

        let candidateKey = canonicalKey(for: trimmedName)
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        if topics.contains(where: {
            $0.id != excludedID && canonicalKey(for: $0.name) == candidateKey
        }) {
            throw ServiceError.duplicateName(trimmedName)
        }
        return trimmedName
    }

    private func canonicalKey(for name: String) -> String {
        name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func requireExisting(_ topic: TopicRecord, context: ModelContext) throws {
        let topicID = topic.id
        let descriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { candidate in
                candidate.id == topicID
            }
        )
        guard try context.fetchCount(descriptor) == 1 else {
            throw ServiceError.topicNotFound
        }
    }

    private func exportDiagnostics(from context: ModelContext) {
        guard let diagnosticExporter else { return }
        try? diagnosticExporter.export(from: context)
    }
}
