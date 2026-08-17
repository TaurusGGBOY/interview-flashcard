import Foundation

/// Normalization helpers for topic names.
///
/// Topic names are user-entered and model-echoed text that can carry invisible
/// spacing characters. The concrete failure that motivated this type: names
/// copied or generated with U+2006 SIX-PER-EM SPACE (a justification artifact)
/// were persisted verbatim, so a model response saying `system design` (normal
/// space) could not match a stored topic `system design` (U+2006), and every
/// candidate in a chunk was rejected by the whitelist validation.
///
/// Matching and duplicate detection therefore use a whitespace-insensitive key;
/// display names are cleaned before they are persisted.
enum TopicNameNormalization {
    /// Canonical key used for matching and duplicate detection. Removes every
    /// whitespace character (including U+2006 and the rest of the Unicode
    /// space family) and folds case and diacritics, so `system design`,
    /// `System Design`, `system\u{2006}design`, and `systemdesign` all compare
    /// equal.
    static func key(_ name: String) -> String {
        name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .filter { !$0.isWhitespace }
    }

    /// Display-safe name for storage: removes invisible formatting characters
    /// (U+2000-U+200A space family, NBSP, narrow no-break space, medium
    /// mathematical space, ideographic space, and zero-width format
    /// characters), then collapses remaining whitespace runs to a single ASCII
    /// space and trims.
    static func cleanedForStorage(_ name: String) -> String {
        let withoutInvisible = name.filter { !isInvisibleSpacing($0) }
        return withoutInvisible
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// One-time repair for legacy topic names already persisted with invisible
    /// spacing. A curated override recovers the intended display name for the
    /// names that were broken in the wild (their U+2006 was inserted between
    /// every letter); the generic fallback removes invisible spacing and
    /// collapses whitespace.
    static func repairedLegacyName(_ name: String) -> String {
        if let intended = legacyRepairMap[name] {
            return intended
        }
        return cleanedForStorage(name)
    }

    /// Invisible characters that can appear in copied/justified text and must
    /// never survive into a stored topic name.
    private static func isInvisibleSpacing(_ character: Character) -> Bool {
        switch character {
        case "\u{00A0}", "\u{202F}", "\u{205F}", "\u{3000}",
             "\u{200B}", "\u{200C}", "\u{200D}",
             "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}",
             "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}",
             "\u{2008}", "\u{2009}", "\u{200A}":
            true
        default:
            false
        }
    }

    private static let legacyRepairMap: [String: String] = [
        "re\u{2006}di\u{2006}s": "redis",
        "m\u{2006}y\u{2006}s\u{2006}q\u{2006}l": "mysql",
        "mo\u{2006}n\u{2006}go\u{2006}d\u{2006}b": "mongodb",
        "elastic\u{2006}sea\u{2006}r\u{2006}ch": "elasticsearch",
        "po\u{2006}s\u{2006}t\u{2006}g\u{2006}re\u{2006}s\u{2006}q\u{2006}l": "postgresql",
        "jv\u{2006}m": "jvm",
        "high\u{2006}con\u{2006}cu\u{2006}r\u{2006}ren\u{2006}c\u{2006}y": "high concurrency",
        "computer\u{2006}networks": "computer networks",
        "opera\u{2006}ting\u{2006}s\u{2006}y\u{2006}s\u{2006}te\u{2006}m\u{2006}s": "operating systems",
        "da\u{2006}ta\u{2006}structures\u{2006}7\u{2006}a\u{2006}l\u{2006}go\u{2006}ri\u{2006}t\u{2006}h\u{2006}m\u{2006}s": "data structures 7 algorithms",
        "system\u{2006}design": "system design",
    ]
}
