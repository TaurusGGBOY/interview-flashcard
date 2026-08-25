import CryptoKit
import Foundation

actor StubAIClient: AIClient {
    enum Mode: String, CaseIterable, Equatable, Sendable {
        case success
        case transientOnce = "transient-once"
        case refineAlwaysFail = "refine-always-fail"
        case processingPaused = "processing-paused"
        case processingDelayed = "processing-delayed"
        case evaluationInvalid = "evaluation-invalid"
        case reclassifyBatchFailure = "reclassify-batch-failure"

        static func from(arguments: [String]) -> Mode {
            for flag in ["--stub-mode", "-IFStubMode"] {
                guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                    continue
                }
                return Mode(rawValue: arguments[index + 1]) ?? .success
            }
            return .success
        }
    }

    private let mode: Mode
    private var transientFailures: Set<AIOperation> = []

    init(mode: Mode = .success) {
        self.mode = mode
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try failIfConfigured(operation: .decompose)
        let topicName = topicName(
            for: request.ownedMarkdown,
            availableTopicNames: request.availableTopicNames
        )
        let sections = headingSections(in: request.ownedMarkdown)
        if !sections.isEmpty {
            let candidates = sections.enumerated().map { index, section in
                let anchor = SourceAnchor(
                    sourceDocumentID: request.sourceDocumentID,
                    chunkID: request.chunkID,
                    startOffset: request.ownedStartOffset + section.localUTF16Offset,
                    endOffset: request.ownedStartOffset + section.localUTF16Offset + section.anchor.utf16.count,
                    exactQuote: section.anchor
                )
                return CandidateDraft(
                    id: derivedUUID(base: request.requestID, salt: index + 1),
                    ordinal: index,
                    question: question(for: section.title),
                    sourceBackedAnswerMaterial: section.material,
                    sourceAnchors: [anchor],
                    topicName: request.availableTopicNames.isEmpty ? nil : topicName
                )
            }
            return DecomposeResponse(candidates: candidates, completionStatus: .complete)
        }
        let quote = sourceQuote(from: request.ownedMarkdown)
        guard !quote.isEmpty else {
            return DecomposeResponse(candidates: [], completionStatus: .complete)
        }
        let anchor = SourceAnchor(
            sourceDocumentID: request.sourceDocumentID,
            chunkID: request.chunkID,
            startOffset: request.ownedStartOffset,
            endOffset: request.ownedStartOffset + quote.utf16.count,
            exactQuote: quote
        )
        let candidates = (0..<3).map { index in
            CandidateDraft(
                id: derivedUUID(base: request.requestID, salt: index + 1),
                ordinal: index,
                question: "样例面试题 \(index + 1)：请解释资料中的核心概念。",
                sourceBackedAnswerMaterial: quote,
                sourceAnchors: [anchor],
                topicName: request.availableTopicNames.isEmpty ? nil : topicName
            )
        }
        return DecomposeResponse(candidates: candidates, completionStatus: .complete)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try failIfConfigured(operation: .referenceAnswer)
        let answer = seniorReferenceAnswer(
            from: request.sourceBackedMaterial.isEmpty
                ? request.question
                : request.sourceBackedMaterial
        )
        let keyPoints: [String]
        if case let .success(points) = FullScoreAnswerQualityPolicy.assess(answer) {
            keyPoints = points
        } else {
            keyPoints = []
        }
        return ReferenceAnswerResponse(
            answerText: answer,
            keyPoints: keyPoints,
            modelID: "stub-deterministic-v1",
            promptVersion: PromptCatalog.referenceAnswerVersion,
            completionStatus: .complete
        )
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try failIfConfigured(operation: .refine)
        if mode == .refineAlwaysFail {
            throw AIError.invalidResponse("Injected refine failure")
        }
        let cards = request.candidates.map { candidate in
            RefinedCardDraft(
                id: derivedUUID(base: request.requestID, salt: candidate.ordinal + 101),
                mergedCandidateIDs: [candidate.id],
                question: candidate.question,
                fullScoreAnswer: seniorReferenceAnswer(from: candidate.sourceBackedAnswerMaterial),
                topicName: candidate.topicName.flatMap { request.availableTopicNames.contains($0) ? $0 : nil }
                    ?? topicName(
                        for: candidate.question + "\n" + candidate.sourceBackedAnswerMaterial,
                        availableTopicNames: request.availableTopicNames
                    ),
                sourceAnchors: candidate.sourceAnchors
            )
        }
        return RefineResponse(cards: cards, completionStatus: .complete)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try failIfConfigured(operation: .reclassify)
        if mode == .reclassifyBatchFailure {
            throw AIError.invalidResponse("Injected reclassification batch failure")
        }
        let topic = request.availableTopicNames.first(where: { $0 != "Others" })
            ?? request.availableTopicNames.first
            ?? "Others"
        return ReclassifyResponse(
            assignments: request.cards.map { .init(cardID: $0.id, topicName: topic) },
            completionStatus: .complete
        )
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try failIfConfigured(operation: .polish)
        if mode == .processingPaused {
            throw AIError.processingPaused
        }
        let polished = request.rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
        return PolishResponse(
            polishedText: polished,
            edits: polished == request.rawText
                ? []
                : [.init(original: request.rawText, replacement: polished, reason: "清理首尾空白和重复空格")],
            suspectedTranscriptionIssues: [],
            introducedClaims: [],
            needsUserReview: false,
            warnings: [],
            modelID: "stub-deterministic-v1",
            promptVersion: PromptCatalog.polishVersion,
            completionStatus: .complete
        )
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try failIfConfigured(operation: .evaluate)
        if mode == .processingPaused {
            throw AIError.processingPaused
        }
        if mode == .processingDelayed {
            try await Task.sleep(for: .seconds(5))
        }
        let trimmed = request.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return EvaluationResponse(
                scorable: false,
                notScorableReason: "回答没有足够文字",
                dimensions: [],
                factualErrors: [],
                strengths: [],
                gapsAndErrors: ["没有可评分内容"],
                improvements: ["先给出核心结论"],
                polishOnlyClaims: [],
                confidence: 1,
                scoreRange: .init(low: 0, high: 0),
                warnings: [],
                modelID: "stub-deterministic-v1",
                promptVersion: PromptCatalog.evaluateVersion,
                rubricVersion: request.rubric.version,
                completionStatus: .complete
            )
        }

        let evidenceQuote = String(trimmed.prefix(80))
        let fixedScores: [(ScoreDimension, Int)] = [
            (.correctness, 80),
            (.coverage, 60),
            (.reasoning, 80),
            (.structure, 80),
            (.tradeoffs, 70),
            (.precision, 100)
        ]
        var dimensions = fixedScores.map { key, score in
            EvaluationDimension(
                key: key,
                score: score,
                evidence: [.init(quote: evidenceQuote, explanation: "确定性测试证据")],
                missedPoints: score == 100 ? [] : ["可补充更多边界条件"],
                feedback: "确定性 Stub 评分"
            )
        }
        if mode == .evaluationInvalid {
            dimensions.removeAll { $0.key == .precision }
        }
        return EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: dimensions,
            factualErrors: [],
            strengths: ["给出了核心结论"],
            gapsAndErrors: ["覆盖度还可提高"],
            improvements: ["补充边界、示例和取舍"],
            polishOnlyClaims: request.introducedClaims.map(\.text),
            confidence: 0.9,
            scoreRange: .init(low: 70, high: 80),
            warnings: [],
            modelID: "stub-deterministic-v1",
            promptVersion: PromptCatalog.evaluateVersion,
            rubricVersion: request.rubric.version,
            completionStatus: .complete
        )
    }

    private func failIfConfigured(operation: AIOperation) throws {
        guard mode == .transientOnce, !transientFailures.contains(operation) else {
            return
        }
        transientFailures.insert(operation)
        throw AIError.rateLimited
    }

    private func sourceQuote(from markdown: String) -> String {
        String(markdown.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    /// Keep the deterministic importer fixture compatible with the production
    /// reference-answer quality gate.  The real provider is instructed to
    /// author this structure; the stub mirrors that contract while retaining a
    /// bounded excerpt of the source material for traceability in UI tests.
    private func seniorReferenceAnswer(from material: String) -> String {
        let excerpt = material
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix("#") {
                    return String(text.drop(while: { $0 == "#" || $0 == " " }))
                }
                return text
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let source = String(excerpt.prefix(280))

        return """
        ## 结论
        原文材料摘录：\(source)。回答应通过材料中的步骤或约束解释结果，并把适用范围说清楚。这样既保留来源依据，也能让面试官检查机制是否成立。

        ## 核心要点
        - 通过原文描述的步骤或机制解释为什么会得到该结果，从而避免只背结论。
        - 根据材料中的输入、状态或边界条件拆解流程，同时说明正常路径与异常路径。
        - 结合一致性、延迟、成本或复杂度做工程取舍，并用测试或观测验证关键假设。

        ## 边界与取舍
        材料中的具体约束决定方案边界；当输入异常、依赖失败或资源受限时，需要处理失败、设置超时并提供降级路径。更强的一致性通常带来延迟和成本，简单方案则可能牺牲覆盖度，因此应结合业务风险选择，并继续用监控和压测验证。
        """
    }

    private struct HeadingSection {
        let title: String
        let anchor: String
        let material: String
        let localUTF16Offset: Int
    }

    private func headingSections(in markdown: String) -> [HeadingSection] {
        var headings: [(title: String, anchor: String, start: String.Index, offset: Int)] = []
        var lineStart = markdown.startIndex
        var insideFence = false

        while lineStart < markdown.endIndex {
            let lineEnd = markdown[lineStart...].firstIndex(of: "\n") ?? markdown.endIndex
            let line = String(markdown[lineStart..<lineEnd])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
            } else if !insideFence, trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if isFixtureQuestionHeading(title) {
                    headings.append((
                        title: title,
                        anchor: trimmed,
                        start: lineStart,
                        offset: markdown.utf16.distance(
                            from: markdown.utf16.startIndex,
                            to: lineStart.samePosition(in: markdown.utf16) ?? markdown.utf16.startIndex
                        )
                    ))
                }
            }
            if lineEnd == markdown.endIndex { break }
            lineStart = markdown.index(after: lineEnd)
        }

        return headings.enumerated().map { index, heading in
            let end = index + 1 < headings.count ? headings[index + 1].start : markdown.endIndex
            let material = String(markdown[heading.start..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return HeadingSection(
                title: heading.title,
                anchor: heading.anchor,
                material: material,
                localUTF16Offset: heading.offset
            )
        }
    }

    private func isFixtureQuestionHeading(_ title: String) -> Bool {
        if ["JVM 类加载阶段", "HashMap 扩容", "CAP 取舍"].contains(title) {
            return true
        }
        guard title.count >= 3, title.first == "Q" else { return false }
        return title.dropFirst().prefix(2).allSatisfy(\.isNumber)
    }

    private func question(for title: String) -> String {
        switch title {
        case "JVM 类加载阶段":
            return "JVM 类加载包含哪些阶段？"
        case "HashMap 扩容":
            return "HashMap 如何扩容？"
        case "CAP 取舍":
            return "CAP 定理中的取舍是什么？"
        default:
            return title.hasSuffix("？") || title.hasSuffix("?") ? title : "\(title) 的核心问题是什么？"
        }
    }

    private func topicName(for text: String, availableTopicNames: [String]) -> String {
        guard !availableTopicNames.isEmpty else { return "Others" }
        let normalizedText = text.lowercased()
        if normalizedText.contains("kubernetes") || normalizedText.contains("k8s") {
            if let kubernetesTopic = availableTopicNames.first(where: { name in
                let normalizedName = name.lowercased()
                return normalizedName.contains("kubernetes") || normalizedName == "k8s"
            }) {
                return kubernetesTopic
            }
        }
        return availableTopicNames.first(where: { $0 != "Others" })
            ?? availableTopicNames.first
            ?? "Others"
    }

    private func derivedUUID(base: UUID, salt: Int) -> UUID {
        let digest = SHA256.hash(data: Data("\(base.uuidString):\(salt)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
