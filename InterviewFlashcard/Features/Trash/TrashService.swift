import Foundation
import SwiftData

@MainActor
struct TrashService {
    struct DeletionImpact: Equatable, Sendable {
        let questionID: UUID
        let attemptCount: Int
        let evaluationCount: Int
        let audioCount: Int

        var summary: String {
            "将永久删除 1 道题、\(attemptCount) 条回答、\(evaluationCount) 条评分和 \(audioCount) 个录音。此操作不可撤销。"
        }
    }

    enum TrashError: LocalizedError, Equatable {
        case questionNotFound
        case alreadyTrashed
        case notTrashed

        var errorDescription: String? {
            switch self {
            case .questionNotFound: "题目不存在。"
            case .alreadyTrashed: "题目已经在回收站。"
            case .notTrashed: "只能永久删除回收站中的题目。"
            }
        }
    }

    typealias RemoveAudio = @Sendable (String) throws -> Void

    let now: @Sendable () -> Date
    let removeAudio: RemoveAudio

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        removeAudio: @escaping RemoveAudio = TrashService.removeAudioFile
    ) {
        self.now = now
        self.removeAudio = removeAudio
    }

    func moveToTrash(cardID: UUID, context: ModelContext) throws {
        let card = try card(cardID, context: context)
        guard card.trashedAt == nil else { throw TrashError.alreadyTrashed }
        card.trashedAt = now()
        card.updatedAt = now()
        try context.save()
    }

    func restore(cardID: UUID, context: ModelContext) throws {
        let card = try card(cardID, context: context)
        guard card.trashedAt != nil else { throw TrashError.notTrashed }
        card.trashedAt = nil
        card.updatedAt = now()
        try context.save()
    }

    func deletionImpact(cardID: UUID, context: ModelContext) throws -> DeletionImpact {
        let card = try card(cardID, context: context)
        return DeletionImpact(
            questionID: card.id,
            attemptCount: card.attempts.count,
            evaluationCount: card.attempts.reduce(0) { $0 + $1.evaluations.count },
            audioCount: card.attempts.reduce(0) { $0 + ($1.audioAsset == nil ? 0 : 1) }
        )
    }

    func permanentlyDelete(cardID: UUID, context: ModelContext) async throws {
        let card = try card(cardID, context: context)
        guard card.trashedAt != nil else { throw TrashError.notTrashed }
        let audioPaths = card.attempts.compactMap(\.audioAsset?.relativePath)
        context.delete(card)
        try context.save()
        for path in audioPaths {
            try removeAudio(path)
        }
    }

    private func card(_ id: UUID, context: ModelContext) throws -> QuestionCardRecord {
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        guard let card = cards.first(where: { $0.id == id }) else { throw TrashError.questionNotFound }
        return card
    }

    nonisolated static func removeAudioFile(_ relativePath: String) throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InterviewFlashcard", isDirectory: true)
        let url = base.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
