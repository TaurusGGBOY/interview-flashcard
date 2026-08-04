import SwiftData
@testable import InterviewFlashcard

enum TestModelContainer {
    @MainActor
    static func make() throws -> ModelContainer {
        try AppModelContainer.make(inMemory: true)
    }
}
