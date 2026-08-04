import Foundation
import Markdown

struct MarkdownImportChunk: Equatable, Sendable {
    let ordinal: Int
    let headingPath: [String]
    let ownedMarkdown: String
    let contextBefore: String
    let contextAfter: String
    let ownedStartOffset: Int
    let ownedEndOffset: Int
    let ownedStartLine: Int
    let ownedEndLine: Int
}

struct MarkdownChunker: Sendable {
    struct Configuration: Equatable, Sendable {
        var targetCharacters: Int = 12_000
        var overlapCharacters: Int = 1_200

        init(targetCharacters: Int = 12_000, overlapCharacters: Int = 1_200) {
            self.targetCharacters = targetCharacters
            self.overlapCharacters = overlapCharacters
        }
    }

    enum ChunkError: Error, Equatable {
        case invalidConfiguration
    }

    let configuration: Configuration

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    func chunks(markdown: String) throws -> [MarkdownImportChunk] {
        guard configuration.targetCharacters > 0,
              configuration.overlapCharacters >= 0,
              configuration.overlapCharacters < configuration.targetCharacters else {
            throw ChunkError.invalidConfiguration
        }
        guard !markdown.isEmpty else { return [] }

        // swift-markdown is the syntax authority. Source slicing remains byte-for-byte
        // against the original text so source anchors can be independently verified.
        let document = Document(parsing: markdown)
        let lines = sourceLines(in: markdown)
        let structuralRanges = headingSectionRanges(
            document: document,
            lines: lines,
            documentLength: markdown.utf16.count
        )
        let astBlockBoundaries = document.children.compactMap { child in
            child.range.map { utf16Offset(at: $0.lowerBound, lines: lines) }
        } + [markdown.utf16.count]
        let atomicRanges = structuralRanges.flatMap {
            splitOversizedRange(
                $0,
                lines: lines,
                astBlockBoundaries: astBlockBoundaries,
                target: configuration.targetCharacters
            )
        }
        let ownedRanges = pack(ranges: atomicRanges, target: configuration.targetCharacters)

        return ownedRanges.enumerated().map { ordinal, range in
            let owned = substring(markdown, utf16Range: range)
            let beforeRange = max(0, range.lowerBound - configuration.overlapCharacters)..<range.lowerBound
            let afterRange = range.upperBound..<min(markdown.utf16.count, range.upperBound + configuration.overlapCharacters)
            return MarkdownImportChunk(
                ordinal: ordinal,
                headingPath: headingPath(at: range.lowerBound, lines: lines),
                ownedMarkdown: owned,
                contextBefore: substring(markdown, utf16Range: beforeRange),
                contextAfter: substring(markdown, utf16Range: afterRange),
                ownedStartOffset: range.lowerBound,
                ownedEndOffset: range.upperBound,
                ownedStartLine: lineNumber(at: range.lowerBound, lines: lines),
                ownedEndLine: lineNumber(at: max(range.lowerBound, range.upperBound - 1), lines: lines)
            )
        }
    }

    private struct SourceLine: Sendable {
        let text: String
        let startOffset: Int
        let endOffset: Int
        let lineNumber: Int
    }

    private func sourceLines(in markdown: String) -> [SourceLine] {
        let parts = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var offset = 0
        return parts.enumerated().map { index, part in
            let hasNewline = index < parts.count - 1
            let text = String(part) + (hasNewline ? "\n" : "")
            defer { offset += text.utf16.count }
            return SourceLine(
                text: text,
                startOffset: offset,
                endOffset: offset + text.utf16.count,
                lineNumber: index + 1
            )
        }
    }

    private func headingSectionRanges(
        document: Document,
        lines: [SourceLine],
        documentLength: Int
    ) -> [Range<Int>] {
        guard !lines.isEmpty else { return [] }
        var starts = [0] + document.children.compactMap { child -> Int? in
            guard child is Heading, let range = child.range else { return nil }
            return utf16Offset(at: range.lowerBound, lines: lines)
        }
        let needsHeadingFallback = starts.count == 1

        // A malformed node range should not make import impossible. The fallback
        // scanner is fence-aware and only supplies missing heading boundaries.
        var fence: String?
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentFence = fence {
                if trimmed.hasPrefix(currentFence) {
                    fence = nil
                }
                continue
            }
            if let marker = fenceMarker(in: trimmed) {
                fence = marker
                continue
            }
            if needsHeadingFallback, isHeading(trimmed), line.startOffset > 0 {
                starts.append(line.startOffset)
            }
        }

        let uniqueStarts = Array(Set(starts)).sorted()
        return uniqueStarts.enumerated().compactMap { index, start in
            let end = index + 1 < uniqueStarts.count ? uniqueStarts[index + 1] : documentLength
            return start < end ? start..<end : nil
        }
    }

    private func splitOversizedRange(
        _ range: Range<Int>,
        lines: [SourceLine],
        astBlockBoundaries: [Int],
        target: Int
    ) -> [Range<Int>] {
        guard range.count > target else { return [range] }
        let relevantLines = lines.filter { $0.startOffset >= range.lowerBound && $0.endOffset <= range.upperBound }
        var fence: String?
        var safeBoundaries: [Int] = []

        for line in relevantLines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentFence = fence {
                if trimmed.hasPrefix(currentFence) {
                    fence = nil
                    safeBoundaries.append(line.endOffset)
                }
                continue
            }
            if let marker = fenceMarker(in: trimmed) {
                fence = marker
                continue
            }
            safeBoundaries.append(line.endOffset)
        }

        var result: [Range<Int>] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let desiredEnd = min(start + target, range.upperBound)
            if desiredEnd == range.upperBound {
                result.append(start..<range.upperBound)
                break
            }
            let astEnd = astBlockBoundaries.last(where: {
                $0 > start && $0 <= desiredEnd && $0 <= range.upperBound
            })
            let end = astEnd
                ?? safeBoundaries.last(where: { $0 > start && $0 <= desiredEnd })
                ?? safeBoundaries.first(where: { $0 > desiredEnd })
                ?? range.upperBound
            result.append(start..<end)
            start = end
        }
        return result
    }

    private func pack(ranges: [Range<Int>], target: Int) -> [Range<Int>] {
        guard let first = ranges.first else { return [] }
        var packed: [Range<Int>] = []
        var currentStart = first.lowerBound
        var currentEnd = first.upperBound

        for range in ranges.dropFirst() {
            let proposedLength = range.upperBound - currentStart
            if proposedLength <= target {
                currentEnd = range.upperBound
            } else {
                packed.append(currentStart..<currentEnd)
                currentStart = range.lowerBound
                currentEnd = range.upperBound
            }
        }
        packed.append(currentStart..<currentEnd)
        return packed
    }

    private func headingPath(at offset: Int, lines: [SourceLine]) -> [String] {
        var path: [String] = []
        var fence: String?
        for line in lines where line.startOffset <= offset {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentFence = fence {
                if trimmed.hasPrefix(currentFence) { fence = nil }
                continue
            }
            if let marker = fenceMarker(in: trimmed) {
                fence = marker
                continue
            }
            guard let level = headingLevel(trimmed) else { continue }
            let title = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            if path.count >= level {
                path.removeSubrange((level - 1)..<path.count)
            }
            while path.count < level - 1 {
                path.append("")
            }
            path.append(title)
        }
        return path.filter { !$0.isEmpty }
    }

    private func lineNumber(at offset: Int, lines: [SourceLine]) -> Int {
        lines.last(where: { $0.startOffset <= offset })?.lineNumber ?? 1
    }

    private func utf16Offset(at location: SourceLocation, lines: [SourceLine]) -> Int {
        guard lines.indices.contains(location.line - 1) else {
            return lines.last?.endOffset ?? 0
        }
        let line = lines[location.line - 1]
        let content = line.text.hasSuffix("\n") ? String(line.text.dropLast()) : line.text
        let byteOffset = min(max(0, location.column - 1), content.utf8.count)
        let utf8Index = content.utf8.index(content.utf8.startIndex, offsetBy: byteOffset)
        let stringIndex = String.Index(utf8Index, within: content) ?? content.endIndex
        return line.startOffset + content[..<stringIndex].utf16.count
    }

    private func substring(_ markdown: String, utf16Range: Range<Int>) -> String {
        guard !utf16Range.isEmpty else { return "" }
        let lower = String.Index(utf16Offset: utf16Range.lowerBound, in: markdown)
        let upper = String.Index(utf16Offset: utf16Range.upperBound, in: markdown)
        return String(markdown[lower..<upper])
    }

    private func fenceMarker(in trimmedLine: String) -> String? {
        if trimmedLine.hasPrefix("```") { return "```" }
        if trimmedLine.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private func isHeading(_ line: String) -> Bool {
        headingLevel(line) != nil
    }

    private func headingLevel(_ line: String) -> Int? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count) else { return nil }
        let boundary = line.index(line.startIndex, offsetBy: count)
        guard boundary < line.endIndex, line[boundary].isWhitespace else { return nil }
        return count
    }
}
