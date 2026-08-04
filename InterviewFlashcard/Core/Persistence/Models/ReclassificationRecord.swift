import Foundation
import SwiftData

@Model
final class ReclassificationRunRecord {
    @Attribute(.unique) var id: UUID
    var statusRaw: String
    var totalCards: Int
    var reclassifiedCards: Int
    var failedCards: Int
    var startedAt: Date
    var completedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ReclassificationBatchRecord.run)
    var batches: [ReclassificationBatchRecord] = []

    var status: ReclassificationRunStatus {
        get { ReclassificationRunStatus(rawValue: statusRaw) ?? .completedWithFailures }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        status: ReclassificationRunStatus = .pending,
        totalCards: Int,
        reclassifiedCards: Int = 0,
        failedCards: Int = 0,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.statusRaw = status.rawValue
        self.totalCards = totalCards
        self.reclassifiedCards = reclassifiedCards
        self.failedCards = failedCards
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

@Model
final class ReclassificationBatchRecord {
    @Attribute(.unique) var id: UUID
    var ordinal: Int
    var cardCount: Int
    var statusRaw: String
    var errorSummary: String?
    var createdAt: Date
    var updatedAt: Date
    var run: ReclassificationRunRecord

    var status: BatchStatus {
        get { BatchStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ordinal: Int,
        cardCount: Int,
        status: BatchStatus = .pending,
        errorSummary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        run: ReclassificationRunRecord
    ) {
        self.id = id
        self.ordinal = ordinal
        self.cardCount = cardCount
        self.statusRaw = status.rawValue
        self.errorSummary = errorSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.run = run
    }
}
