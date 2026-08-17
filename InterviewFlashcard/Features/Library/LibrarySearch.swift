import Foundation

@MainActor
enum LibrarySearch {
    static func results(
        from cards: [QuestionCardRecord],
        query: String
    ) -> [QuestionCardRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return cards
            .filter { !$0.isTrashed }
            .filter { card in
                guard !normalizedQuery.isEmpty else { return true }
                return [card.questionText, card.topic.name].contains { value in
                    value.range(
                        of: normalizedQuery,
                        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
                    ) != nil
                }
            }
            .sorted { lhs, rhs in
                if lhs.topic.id != rhs.topic.id {
                    return TopicService.libraryOrder(lhs.topic, rhs.topic)
                }
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
    }
}
