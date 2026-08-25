import Foundation

enum PracticeOrderMode: String, CaseIterable, Codable, Sendable {
    case random
    case ascending
    case descending

    var title: String {
        switch self {
        case .random: "随机做题"
        case .ascending: "顺序做题"
        case .descending: "逆序做题"
        }
    }
}

struct PracticeSettingsSnapshot: Equatable, Sendable {
    var explicitTopicIDs: Set<UUID>?
    var includePracticed: Bool
    var orderMode: PracticeOrderMode
    var progressSequenceKey: String?
    var progressQuestionID: UUID?

    init(
        explicitTopicIDs: Set<UUID>? = nil,
        includePracticed: Bool = false,
        orderMode: PracticeOrderMode = .random,
        progressSequenceKey: String? = nil,
        progressQuestionID: UUID? = nil
    ) {
        self.explicitTopicIDs = explicitTopicIDs
        self.includePracticed = includePracticed
        self.orderMode = orderMode
        self.progressSequenceKey = progressSequenceKey
        self.progressQuestionID = progressQuestionID
    }

    func resolvedTopicIDs(validTopicIDs: Set<UUID>) -> Set<UUID> {
        explicitTopicIDs?.intersection(validTopicIDs) ?? validTopicIDs
    }
}

protocol PracticeSettingsStore: Sendable {
    func load() -> PracticeSettingsSnapshot
    func save(_ snapshot: PracticeSettingsSnapshot)
    func reconcile(validTopicIDs: Set<UUID>) -> PracticeSettingsSnapshot
}

final class UserDefaultsPracticeSettingsStore: PracticeSettingsStore, @unchecked Sendable {
    enum Key {
        static let hasExplicitTopicSelection = "settings.practice.has-explicit-topic-selection"
        static let selectedTopicIDs = "settings.practice.selected-topic-ids"
        static let includePracticed = "settings.practice.include-practiced"
        static let orderMode = "settings.practice.order-mode"
        static let progressSequenceKey = "settings.practice.progress-sequence-key"
        static let progressQuestionID = "settings.practice.progress-question-id"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> PracticeSettingsSnapshot {
        let explicitTopicIDs: Set<UUID>?
        if userDefaults.bool(forKey: Key.hasExplicitTopicSelection) {
            let values = userDefaults.stringArray(forKey: Key.selectedTopicIDs) ?? []
            explicitTopicIDs = Set(values.compactMap(UUID.init(uuidString:)))
        } else {
            explicitTopicIDs = nil
        }
        return PracticeSettingsSnapshot(
            explicitTopicIDs: explicitTopicIDs,
            includePracticed: userDefaults.bool(forKey: Key.includePracticed),
            orderMode: PracticeOrderMode(
                rawValue: userDefaults.string(forKey: Key.orderMode) ?? ""
            ) ?? .random,
            progressSequenceKey: userDefaults.string(forKey: Key.progressSequenceKey),
            progressQuestionID: (userDefaults.string(forKey: Key.progressQuestionID))
                .flatMap(UUID.init(uuidString:))
        )
    }

    func save(_ snapshot: PracticeSettingsSnapshot) {
        userDefaults.set(snapshot.includePracticed, forKey: Key.includePracticed)
        userDefaults.set(snapshot.orderMode.rawValue, forKey: Key.orderMode)
        if let progressSequenceKey = snapshot.progressSequenceKey,
           let progressQuestionID = snapshot.progressQuestionID {
            userDefaults.set(progressSequenceKey, forKey: Key.progressSequenceKey)
            userDefaults.set(progressQuestionID.uuidString, forKey: Key.progressQuestionID)
        } else {
            userDefaults.removeObject(forKey: Key.progressSequenceKey)
            userDefaults.removeObject(forKey: Key.progressQuestionID)
        }
        if let topicIDs = snapshot.explicitTopicIDs {
            userDefaults.set(true, forKey: Key.hasExplicitTopicSelection)
            userDefaults.set(
                topicIDs.map(\.uuidString).sorted(),
                forKey: Key.selectedTopicIDs
            )
        } else {
            userDefaults.removeObject(forKey: Key.hasExplicitTopicSelection)
            userDefaults.removeObject(forKey: Key.selectedTopicIDs)
        }
    }

    func reconcile(validTopicIDs: Set<UUID>) -> PracticeSettingsSnapshot {
        var snapshot = load()
        guard let explicitTopicIDs = snapshot.explicitTopicIDs else {
            return snapshot
        }
        let cleaned = explicitTopicIDs.intersection(validTopicIDs)
        if cleaned != explicitTopicIDs {
            snapshot.explicitTopicIDs = cleaned
            save(snapshot)
        }
        return snapshot
    }
}

final class InMemoryPracticeSettingsStore: PracticeSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: PracticeSettingsSnapshot

    init(snapshot: PracticeSettingsSnapshot = PracticeSettingsSnapshot()) {
        self.snapshot = snapshot
    }

    func load() -> PracticeSettingsSnapshot {
        lock.withLock { snapshot }
    }

    func save(_ snapshot: PracticeSettingsSnapshot) {
        lock.withLock {
            self.snapshot = snapshot
        }
    }

    func reconcile(validTopicIDs: Set<UUID>) -> PracticeSettingsSnapshot {
        lock.withLock {
            guard let explicitTopicIDs = snapshot.explicitTopicIDs else {
                return snapshot
            }
            snapshot.explicitTopicIDs = explicitTopicIDs.intersection(validTopicIDs)
            return snapshot
        }
    }
}
