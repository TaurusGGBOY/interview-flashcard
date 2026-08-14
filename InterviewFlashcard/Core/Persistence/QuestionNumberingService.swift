import SwiftData

@MainActor
struct QuestionNumberingService {
    func nextNumber(context: ModelContext) throws -> Int {
        let cards = try context.fetch(FetchDescriptor<QuestionCardRecord>())
        let largestNumber = cards
            .compactMap(\.questionNumber)
            .filter { $0 > 0 }
            .max() ?? 0
        return largestNumber + 1
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

        var number = try nextNumber(context: context)
        for card in unnumberedCards {
            card.questionNumber = number
            number += 1
        }
    }
}
