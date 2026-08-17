import Foundation
import SwiftData

@MainActor
struct QuestionNumberingService {
    private static let nextNumberKey = "InterviewFlashcard.QuestionNumbering.nextNumber"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func nextNumber(context: ModelContext) throws -> Int {
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let largestNumber = cards
            .compactMap(\.questionNumber)
            .filter { $0 > 0 }
            .max() ?? 0
        let nextNumber = max(
            max(defaults.integer(forKey: Self.nextNumberKey), 1),
            largestNumber + 1
        )
        defaults.set(nextNumber + 1, forKey: Self.nextNumberKey)
        return nextNumber
    }

    func backfillIfNeeded(context: ModelContext) throws {
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let unnumberedCards = cards
            .filter { $0.questionNumber == nil }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let largestNumber = cards
            .compactMap(\.questionNumber)
            .filter { $0 > 0 }
            .max() ?? 0
        var number = max(
            max(defaults.integer(forKey: Self.nextNumberKey), 1),
            largestNumber + 1
        )
        defaults.set(number, forKey: Self.nextNumberKey)
        for card in unnumberedCards {
            card.questionNumber = number
            number += 1
        }
        defaults.set(number, forKey: Self.nextNumberKey)
    }
}
