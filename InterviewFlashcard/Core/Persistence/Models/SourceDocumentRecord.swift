import Foundation
import SwiftData

@Model
final class SourceDocumentRecord {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var sourcePath: String?
    var contentHash: String
    var importerVersion: String
    var importedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ImportRunRecord.sourceDocument)
    var importRuns: [ImportRunRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \QuestionCardRecord.sourceDocument)
    var cards: [QuestionCardRecord] = []

    init(
        id: UUID = UUID(),
        fileName: String,
        sourcePath: String? = nil,
        contentHash: String,
        importerVersion: String,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.sourcePath = sourcePath
        self.contentHash = contentHash
        self.importerVersion = importerVersion
        self.importedAt = importedAt
    }
}
