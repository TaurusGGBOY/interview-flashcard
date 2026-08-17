import Foundation
import XCTest

final class MarkdownChunkerTests: XCTestCase {
    func testDefaultConfigurationKeepsOwnedChunkBoundedAndContextCompact() {
        let configuration = MarkdownChunker.Configuration()

        XCTAssertEqual(configuration.targetCharacters, 10_000)
        XCTAssertEqual(configuration.overlapCharacters, 400)
    }

    func testChunkerPreservesCodeBlockAndAddsReadOnlyOverlap() throws {
        let longMarkdown = makeLongMarkdown(sectionCount: 12, explanationLength: 320)
            + "\n## 代码示例\n\n```swift\nlet marker = \"## 这不是题目\"\nprint(marker)\n```\n"
        let chunks = try MarkdownChunker(
            configuration: .init(targetCharacters: 900, overlapCharacters: 180)
        ).chunks(markdown: longMarkdown)

        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        XCTAssertTrue(chunks.allSatisfy { chunk in
            !chunk.ownedMarkdown.contains("```swift\n") || chunk.ownedMarkdown.contains("\n```\n")
        })
        XCTAssertEqual(String(chunks[1].contextBefore.suffix(180)), String(chunks[0].ownedMarkdown.suffix(180)))
        XCTAssertEqual(chunks.map(\.ordinal), Array(chunks.indices))
        XCTAssertEqual(chunks.first?.ownedStartOffset, 0)
        XCTAssertEqual(chunks.last?.ownedEndOffset, longMarkdown.utf16.count)
        XCTAssertTrue(zip(chunks, chunks.dropFirst()).allSatisfy { pair in
            pair.0.ownedEndOffset == pair.1.ownedStartOffset
        })
    }

    func testFakeHeadingInsideFenceDoesNotStartStructuralSection() throws {
        let markdown = """
        # 示例

        ## 真题

        答案材料。

        ```swift
        ## 这不是题目
        let value = 1
        ```

        ## 第二题

        更多材料。
        """
        let chunks = try MarkdownChunker(
            configuration: .init(targetCharacters: 80, overlapCharacters: 10)
        ).chunks(markdown: markdown)

        XCTAssertEqual(chunks.filter { $0.headingPath.last == "这不是题目" }.count, 0)
        XCTAssertTrue(chunks.allSatisfy { chunk in
            !chunk.ownedMarkdown.contains("```swift") || chunk.ownedMarkdown.contains("\n```\n")
        })
    }

    func testInvalidConfigurationIsRejected() {
        XCTAssertThrowsError(
            try MarkdownChunker(
                configuration: .init(targetCharacters: 100, overlapCharacters: 100)
            ).chunks(markdown: "# A")
        ) { error in
            XCTAssertEqual(error as? MarkdownChunker.ChunkError, .invalidConfiguration)
        }
    }

    private func makeLongMarkdown(sectionCount: Int, explanationLength: Int) -> String {
        (1...sectionCount).map { index in
            let explanation = String(repeating: "第\(index)题的来源说明用于测试结构感知分片。", count: explanationLength / 18 + 1)
            return "## Q\(String(format: "%02d", index)) 唯一问题\n\n- 关键点 A\n- 关键点 B\n\n\(explanation.prefix(explanationLength))\n"
        }.joined(separator: "\n")
    }
}
