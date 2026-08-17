import Foundation
import SwiftData

/// Repairs topic records that were persisted with invisible spacing characters
/// (for example U+2006 SIX-PER-EM SPACE from copied or justified text).
///
/// Such names are invisible to the user and break the exact-name whitelist
/// contract with the AI provider: the model echoes `system design` with a
/// normal space while the store contains `system\u{2006}design`, so every
/// candidate in a chunk is rejected as `unknownTopic`.
///
/// The pass is idempotent: it renames each polluted topic to its cleaned
/// display name and, when two topics collide under the normalized key, moves
/// all cards into the surviving topic and deletes the duplicate. The system
/// topic (Others) is never renamed or deleted.
@MainActor
enum TopicNameHygiene {
    static func repair(context: ModelContext, now: Date = Date()) throws {
        let topics = try context.fetch(FetchDescriptor<TopicRecord>())
        let nonSystemTopics = topics.filter { $0.systemKind != .others }
        guard !nonSystemTopics.isEmpty else { return }

        // Group by the whitespace-insensitive key, preferring an already-clean
        // display name as the keeper of each group.
        var groups: [String: [TopicRecord]] = [:]
        for topic in nonSystemTopics {
            let key = TopicNameNormalization.key(
                TopicNameNormalization.repairedLegacyName(topic.name)
            )
            groups[key, default: []].append(topic)
        }

        var changed = false
        for members in groups.values {
            guard let keeper = pickKeeper(members) else { continue }
            let repairedName = TopicNameNormalization.repairedLegacyName(keeper.name)
            if keeper.name != repairedName {
                keeper.name = repairedName
                keeper.updatedAt = now
                changed = true
            }

            for duplicate in members where duplicate.id != keeper.id {
                for card in Array(duplicate.cards) {
                    card.topic = keeper
                    card.updatedAt = now
                }
                context.delete(duplicate)
                changed = true
            }
        }

        if changed {
            try context.save()
        }
    }

    private static func pickKeeper(_ members: [TopicRecord]) -> TopicRecord? {
        members.first { TopicNameNormalization.repairedLegacyName($0.name) == $0.name }
            ?? members.first
    }
}
