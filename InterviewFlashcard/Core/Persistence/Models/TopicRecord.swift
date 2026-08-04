import Foundation
import SwiftData

@Model
final class TopicRecord {
    static let othersID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Attribute(.unique) var id: UUID
    var name: String
    var systemKindRaw: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .deny, inverse: \QuestionCardRecord.topic)
    var cards: [QuestionCardRecord] = []

    var systemKind: SystemTopicKind? {
        get { systemKindRaw.flatMap(SystemTopicKind.init(rawValue:)) }
        set { systemKindRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        systemKind: SystemTopicKind? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemKindRaw = systemKind?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
