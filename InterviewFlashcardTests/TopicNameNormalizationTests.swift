import XCTest

final class TopicNameNormalizationTests: XCTestCase {
    func testKeyIsWhitespaceInsensitiveAndCaseFoldInsensitive() {
        XCTAssertEqual(
            TopicNameNormalization.key("system design"),
            TopicNameNormalization.key("system\u{2006}design")
        )
        XCTAssertEqual(
            TopicNameNormalization.key("System Design"),
            TopicNameNormalization.key("systemdesign")
        )
        XCTAssertEqual(
            TopicNameNormalization.key("m\u{2006}y\u{2006}s\u{2006}q\u{2006}l"),
            "mysql"
        )
        XCTAssertEqual(TopicNameNormalization.key("data\u{00A0}structures"), "datastructures")
        XCTAssertEqual(TopicNameNormalization.key("  Java  "), "java")
    }

    func testCleanedForStorageRemovesInvisibleSpacingAndCollapsesWhitespace() {
        XCTAssertEqual(TopicNameNormalization.cleanedForStorage("  Java  "), "Java")
        XCTAssertEqual(
            TopicNameNormalization.cleanedForStorage("system\u{2006}design"),
            "systemdesign"
        )
        XCTAssertEqual(
            TopicNameNormalization.cleanedForStorage("m\u{2006}y\u{2006}s\u{2006}q\u{2006}l"),
            "mysql"
        )
        XCTAssertEqual(
            TopicNameNormalization.cleanedForStorage("data\u{2006}structures\u{2006}7\u{2006}algorithms"),
            "datastructures7algorithms"
        )
        XCTAssertEqual(TopicNameNormalization.cleanedForStorage("\u{200B}\u{2006}"), "")
    }

    func testRepairedLegacyNameUsesCuratedIntendedNames() {
        XCTAssertEqual(TopicNameNormalization.repairedLegacyName("m\u{2006}y\u{2006}s\u{2006}q\u{2006}l"), "mysql")
        XCTAssertEqual(TopicNameNormalization.repairedLegacyName("system\u{2006}design"), "system design")
        XCTAssertEqual(
            TopicNameNormalization.repairedLegacyName("computer\u{2006}networks"),
            "computer networks"
        )
        XCTAssertEqual(TopicNameNormalization.repairedLegacyName("redis"), "redis")
    }
}
