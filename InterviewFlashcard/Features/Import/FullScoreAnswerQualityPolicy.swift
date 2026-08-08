import Foundation

/// Quality gate for reference answers produced by a new import or regeneration.
///
/// Historical answers are intentionally not evaluated here.  The policy is used
/// only at the import staging boundary and again immediately before activation.
enum FullScoreAnswerQualityPolicy {
    typealias Error = Rejection

    static let minimumNonWhitespaceCharacters = 120
    static let minimumSentenceCount = 3
    static let minimumKeyPointCount = 3

    enum Rejection: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case tooShort
        case tooFewSentences
        case missingSection(String)
        case insufficientKeyPoints
        case genericDefinition

        var description: String {
            switch self {
            case .tooShort:
                return "满分答案去除空白后少于 120 个字符"
            case .tooFewSentences:
                return "满分答案必须包含至少三句话"
            case let .missingSection(section):
                return "满分答案缺少 Markdown 小节“\(section)”"
            case .insufficientKeyPoints:
                return "“核心要点”必须包含至少三个不重复的非空要点"
            case .genericDefinition:
                return "满分答案不能只有泛泛定义，必须说明机制以及边界或工程取舍"
            }
        }
    }

    /// Returns the distinct, non-empty bullets under “核心要点” on success.
    /// A failure includes a displayable, concrete reason suitable for an import
    /// error summary.
    static func assess(_ answer: String) -> Result<[String], Rejection> {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonWhitespaceCount = trimmed.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
        guard nonWhitespaceCount >= minimumNonWhitespaceCharacters else {
            return .failure(.tooShort)
        }

        let sections = markdownSections(in: trimmed)
        for requiredSection in ["结论", "核心要点", "边界与取舍"] {
            guard sections[requiredSection] != nil else {
                return .failure(.missingSection(requiredSection))
            }
        }

        let keyPoints = distinctBullets(in: sections["核心要点"] ?? "")
        guard keyPoints.count >= minimumKeyPointCount else {
            return .failure(.insufficientKeyPoints)
        }

        guard sentenceCount(in: trimmed) >= minimumSentenceCount else {
            return .failure(.tooFewSentences)
        }

        guard hasMechanismLanguage(in: trimmed),
              hasBoundaryOrTradeoffLanguage(in: sections["边界与取舍"] ?? "") else {
            return .failure(.genericDefinition)
        }

        return .success(keyPoints)
    }

    private static func markdownSections(in answer: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentTitle: String?
        var bodyLines: [String] = []

        func flush() {
            guard let currentTitle else { return }
            sections[currentTitle] = bodyLines.joined(separator: "\n")
        }

        for line in answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title = sectionTitle(from: normalized) {
                flush()
                currentTitle = title
                bodyLines = []
            } else if currentTitle != nil {
                bodyLines.append(line)
            }
        }
        flush()
        return sections
    }

    private static func sectionTitle(from line: String) -> String? {
        guard line.hasPrefix("## ") else { return nil }
        let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func distinctBullets(in body: String) -> [String] {
        var seen = Set<String>()
        var keyPoints: [String] = []

        for line in body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let content = bulletContent(from: trimmed), !content.isEmpty else { continue }
            let normalized = normalizeForComparison(content)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            keyPoints.append(content)
        }
        return keyPoints
    }

    private static func bulletContent(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var digitsEnd = line.startIndex
        while digitsEnd < line.endIndex, line[digitsEnd].isNumber {
            digitsEnd = line.index(after: digitsEnd)
        }
        guard digitsEnd > line.startIndex,
              line[digitsEnd...].hasPrefix(". ") else {
            return nil
        }
        return String(line[line.index(digitsEnd, offsetBy: 2)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeForComparison(_ text: String) -> String {
        var normalized = ""
        normalized.reserveCapacity(text.count)
        for scalar in text.lowercased().unicodeScalars {
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  !CharacterSet.punctuationCharacters.contains(scalar) else { continue }
            normalized.append(String(scalar))
        }
        return normalized
    }

    private static func sentenceCount(in answer: String) -> Int {
        let terminators: Set<Character> = ["。", "！", "？", "!", "?", "."]
        return answer.reduce(into: 0) { count, character in
            if terminators.contains(character) { count += 1 }
        }
    }

    private static func hasMechanismLanguage(in answer: String) -> Bool {
        containsAny(
            in: answer,
            terms: [
                "因为", "由于", "通过", "利用", "机制", "原理", "流程", "从而", "导致", "隔离", "重试", "补偿",
                "幂等", "锁", "actor", "because", "through", "mechanism", "retry", "idempotent"
            ]
        )
    }

    private static func hasBoundaryOrTradeoffLanguage(in answer: String) -> Bool {
        containsAny(
            in: answer,
            terms: [
                "边界", "失败", "异常", "取舍", "权衡", "限制", "代价", "超时", "降级", "上限", "不适用", "风险",
                "一致性", "延迟", "成本", "trade", "failure", "limit", "timeout", "fallback"
            ]
        )
    }

    private static func containsAny(in text: String, terms: [String]) -> Bool {
        let lowercased = text.lowercased()
        return terms.contains { lowercased.contains($0.lowercased()) }
    }
}
