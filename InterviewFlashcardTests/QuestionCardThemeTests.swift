import SwiftUI
import XCTest

final class QuestionCardThemeTests: XCTestCase {
    func testSameQuestionIDAlwaysProducesTheSameTheme() {
        let id = UUID(uuidString: "E8F9C05C-2AA8-42D4-8D6D-36BCE6DDBB7A")!

        let first = QuestionCardTheme.theme(for: id)
        let second = QuestionCardTheme.theme(for: id)

        XCTAssertEqual(first.paletteIndex, second.paletteIndex)
        XCTAssertEqual(first.foregroundKind, second.foregroundKind)
        XCTAssertEqual(first.contrastRatio, second.contrastRatio, accuracy: 0.0001)
    }

    func testDeterministicThemesUseMoreThanOnePredefinedPalette() {
        let ids = (0..<64).map { index in
            UUID(uuidString: String(format: "70000000-0000-0000-0000-%012d", index))!
        }

        let paletteIndices = Set(ids.map { QuestionCardTheme.theme(for: $0).paletteIndex })

        XCTAssertGreaterThanOrEqual(paletteIndices.count, 3)
        XCTAssertGreaterThan(QuestionCardTheme.paletteCount, 1)
    }

    func testEveryPaletteExposesContrastAndForegroundCategory() {
        let ids = (0..<128).map { index in
            UUID(uuidString: String(format: "71000000-0000-0000-0000-%012d", index))!
        }

        for id in ids {
            let theme = QuestionCardTheme.theme(for: id)

            XCTAssertTrue((0..<QuestionCardTheme.paletteCount).contains(theme.paletteIndex))
            XCTAssertGreaterThanOrEqual(theme.contrastRatio, 4.5)
            XCTAssertNotNil(theme.foregroundKind)
        }
    }
}
