import Foundation
import SwiftData

@MainActor
struct TopicService {
    struct TopicDeletionImpact: Equatable, Sendable {
        let topicID: UUID
        let questionCount: Int
        let answerCount: Int
        let evaluationCount: Int
        let audioCount: Int
    }

    enum ServiceError: LocalizedError, Equatable {
        case emptyName
        case duplicateName(String)
        case systemTopicIsImmutable
        case destinationMustDiffer
        case destinationNotFound
        case topicNotFound
        case emptySelection
        case questionNotFound
        case questionIsTrashed

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
            case .emptySelection:
                "请至少选择一个 Topic。"
            case .questionNotFound:
                "要修改的题目已不存在。"
            case .questionIsTrashed:
                "回收站中的题目不能更改 Topic。"
            }
        }
    }

    private let diagnosticExporter: DiagnosticStateExporter?
    private let removeAudio: TrashService.RemoveAudio

    init(
        diagnosticExporter: DiagnosticStateExporter? = nil,
        removeAudio: @escaping TrashService.RemoveAudio = TrashService.removeAudioFile
    ) {
        self.diagnosticExporter = diagnosticExporter
        self.removeAudio = removeAudio
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
        try delete([topic], moveCardsTo: destination, context: context, now: now)
    }

    func delete(
        _ topics: [TopicRecord],
        moveCardsTo destination: TopicRecord,
        context: ModelContext,
        now: Date = Date()
    ) throws {
        guard !topics.isEmpty else {
            throw ServiceError.emptySelection
        }

        let sourceIDs = Set(topics.map(\.id))
        guard topics.allSatisfy({ $0.systemKindRaw == nil }) else {
            throw ServiceError.systemTopicIsImmutable
        }
        guard !sourceIDs.contains(destination.id) else {
            throw ServiceError.destinationMustDiffer
        }

        let sourceDescriptor = FetchDescriptor<TopicRecord>()
        let persistedTopics = try context.fetch(sourceDescriptor)
            .filter { sourceIDs.contains($0.id) }
        guard persistedTopics.count == sourceIDs.count else {
            throw ServiceError.topicNotFound
        }

        let destinationID = destination.id
        let destinationDescriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { candidate in
                candidate.id == destinationID
            }
        )
        guard let persistedDestination = try context.fetch(destinationDescriptor).first else {
            throw ServiceError.destinationNotFound
        }

        for topic in persistedTopics {
            for card in Array(topic.cards) {
                card.topic = persistedDestination
                card.updatedAt = now
            }
            context.delete(topic)
        }
        try context.save()
        exportDiagnostics(from: context)
    }

    func deletionImpact(
        for topic: TopicRecord,
        context: ModelContext
    ) throws -> TopicDeletionImpact {
        let topic = try deletablePersistedTopic(topic, context: context)
        let attempts = topic.cards.flatMap(\.attempts)
        return TopicDeletionImpact(
            topicID: topic.id,
            questionCount: topic.cards.count,
            answerCount: attempts.count,
            evaluationCount: attempts.reduce(0) { $0 + $1.evaluations.count },
            audioCount: attempts.reduce(0) { $0 + ($1.audioAsset == nil ? 0 : 1) }
        )
    }

    func permanentlyDelete(
        topic: TopicRecord,
        context: ModelContext
    ) throws {
        let topic = try deletablePersistedTopic(topic, context: context)
        let audioPaths = topic.cards
            .flatMap(\.attempts)
            .compactMap(\.audioAsset?.relativePath)

        context.delete(topic)
        try context.save()
        exportDiagnostics(from: context)

        for path in audioPaths {
            try removeAudio(path)
        }
    }

    func deletionDestinations(
        for topic: TopicRecord,
        context: ModelContext
    ) throws -> [TopicRecord] {
        try deletionDestinations(for: [topic], context: context)
    }

    func deletionDestinations(
        for topics: [TopicRecord],
        context: ModelContext
    ) throws -> [TopicRecord] {
        guard !topics.isEmpty else {
            throw ServiceError.emptySelection
        }
        guard topics.allSatisfy({ $0.systemKindRaw == nil }) else {
            throw ServiceError.systemTopicIsImmutable
        }
        let sourceIDs = Set(topics.map(\.id))
        return try context.fetch(FetchDescriptor<TopicRecord>())
            .filter { !sourceIDs.contains($0.id) }
            .sorted(by: Self.libraryOrder)
    }

    func moveCards(
        _ cards: [QuestionCardRecord],
        to destination: TopicRecord,
        context: ModelContext,
        now: Date = Date()
    ) throws {
        guard !cards.isEmpty else {
            throw ServiceError.emptySelection
        }

        let cardIDs = Set(cards.map(\.id))
        let persistedCards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
            .filter { cardIDs.contains($0.id) }
        guard persistedCards.count == cardIDs.count else {
            throw ServiceError.questionNotFound
        }
        guard persistedCards.allSatisfy({ $0.trashedAt == nil }) else {
            throw ServiceError.questionIsTrashed
        }

        let destinationID = destination.id
        let destinationDescriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { candidate in
                candidate.id == destinationID
            }
        )
        guard let persistedDestination = try context.fetch(destinationDescriptor).first else {
            throw ServiceError.destinationNotFound
        }

        for card in persistedCards {
            card.topic = persistedDestination
            card.updatedAt = now
        }
        try context.save()
        exportDiagnostics(from: context)
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
        // Invisible spacing characters (for example U+2006 from copied or
        // justified text) must never reach the store: they are not visible to
        // the user and they break the exact-name contract with the AI
        // whitelist. Clean the display name and dedupe with the same
        // whitespace-insensitive key used by AIResponseValidator.
        let cleanedName = TopicNameNormalization.cleanedForStorage(name)
        guard !cleanedName.isEmpty else {
            throw ServiceError.emptyName
        }

        let candidateKey = TopicNameNormalization.key(cleanedName)
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        if topics.contains(where: {
            $0.id != excludedID && TopicNameNormalization.key($0.name) == candidateKey
        }) {
            throw ServiceError.duplicateName(cleanedName)
        }
        return cleanedName
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

    private func deletablePersistedTopic(
        _ topic: TopicRecord,
        context: ModelContext
    ) throws -> TopicRecord {
        guard topic.systemKindRaw == nil else {
            throw ServiceError.systemTopicIsImmutable
        }

        let topicID = topic.id
        let descriptor = FetchDescriptor<TopicRecord>(
            predicate: #Predicate { candidate in
                candidate.id == topicID
            }
        )
        guard let persistedTopic = try context.fetch(descriptor).first else {
            throw ServiceError.topicNotFound
        }
        guard persistedTopic.systemKindRaw == nil else {
            throw ServiceError.systemTopicIsImmutable
        }
        return persistedTopic
    }

    private func exportDiagnostics(from context: ModelContext) {
        guard let diagnosticExporter else { return }
        try? diagnosticExporter.export(from: context)
    }
}
