import Foundation
import XCTest

final class AIResponseValidatorTests: XCTestCase {
    func testEvaluationRejectsMissingDimensionAndComputesNoModelTotal() throws {
        let response = makeEvaluation(
            dimensions: makeDimensions().filter { $0.key != .precision }
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个。"
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .missingDimension(.precision))
        }
    }

    func testEvaluationRejectsCorrectnessCreditThatExistsOnlyInPolishedText() throws {
        var dimensions = makeDimensions()
        let index = try XCTUnwrap(dimensions.firstIndex(where: { $0.key == .correctness }))
        dimensions[index] = EvaluationDimension(
            key: .correctness,
            score: 80,
            evidence: [.init(quote: "分区容错", explanation: "仅由润色新增")],
            missedPoints: ["补充原始回答中的边界"],
            feedback: "不应计分"
        )
        let response = makeEvaluation(dimensions: dimensions)

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 的三个要素包括一致性、可用性和分区容错。"
            )
        ) { error in
            XCTAssertEqual(
                error as? AIResponseValidationError,
                .polishOnlyEvidenceCredited(.correctness, "分区容错")
            )
        }
    }

    func testEvaluationRejectsDuplicateDimensionAndOutOfRangeScore() throws {
        var duplicate = makeDimensions()
        duplicate[5] = duplicate[0]
        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                makeEvaluation(dimensions: duplicate),
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个。"
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .duplicateDimension(.correctness))
        }

        var outOfRange = makeDimensions()
        outOfRange[0] = EvaluationDimension(
            key: .correctness,
            score: 101,
            evidence: [.init(quote: "CAP", explanation: "原文证据")],
            missedPoints: ["补充边界"],
            feedback: "越界"
        )
        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                makeEvaluation(dimensions: outOfRange),
                rubric: EvaluationRubric.general,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个。"
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .scoreOutOfRange(.correctness, 101))
        }
    }

    func testDecomposeRejectsDuplicateIDsMissingAnchorsAndTruncation() throws {
        let sourceID = UUID()
        let chunkID = UUID()
        let request = DecomposeRequest(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            markdown: "CAP theorem",
            ownedStartOffset: 0,
            ownedEndOffset: 11
        )
        let anchor = SourceAnchor(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            startOffset: 0,
            endOffset: 3,
            exactQuote: "CAP"
        )
        let id = UUID()
        let candidate = CandidateDraft(
            id: id,
            ordinal: 0,
            question: "什么是 CAP？",
            sourceBackedAnswerMaterial: "CAP theorem",
            sourceAnchors: [anchor]
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                .init(candidates: [candidate, candidate], completionStatus: .complete),
                for: request
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .duplicateID(id.uuidString))
        }

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                .init(candidates: [], completionStatus: .truncated),
                for: request
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .truncated)
        }
    }

    func testDecomposeTopicWhitelistIgnoresInvisibleSpacing() throws {
        let sourceID = UUID()
        let chunkID = UUID()
        // The stored whitelist contains U+2006 (invisible six-per-em space);
        // the model echoes the name with a normal space.
        let request = DecomposeRequest(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            markdown: "system design",
            ownedStartOffset: 0,
            ownedEndOffset: 13,
            availableTopicNames: ["system\u{2006}design"]
        )
        let anchor = SourceAnchor(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            startOffset: 0,
            endOffset: 6,
            exactQuote: "system"
        )
        let candidate = CandidateDraft(
            id: UUID(),
            ordinal: 0,
            question: "如何设计一个短链接系统？",
            sourceBackedAnswerMaterial: "system design",
            sourceAnchors: [anchor],
            topicName: "system design"
        )

        XCTAssertNoThrow(
            try AIResponseValidator.validate(
                .init(candidates: [candidate], completionStatus: .complete),
                for: request
            )
        )
    }

    func testDecomposeTopicWhitelistAcceptsModelEchoOfInvisibleSpacing() throws {
        let sourceID = UUID()
        let chunkID = UUID()
        // The whitelist is clean; the model echoes the name with U+2006.
        let request = DecomposeRequest(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            markdown: "mysql",
            ownedStartOffset: 0,
            ownedEndOffset: 5,
            availableTopicNames: ["mysql"]
        )
        let anchor = SourceAnchor(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            startOffset: 0,
            endOffset: 5,
            exactQuote: "mysql"
        )
        let candidate = CandidateDraft(
            id: UUID(),
            ordinal: 0,
            question: "MySQL 索引为什么用 B+ 树？",
            sourceBackedAnswerMaterial: "mysql",
            sourceAnchors: [anchor],
            topicName: "m\u{2006}y\u{2006}s\u{2006}q\u{2006}l"
        )

        XCTAssertNoThrow(
            try AIResponseValidator.validate(
                .init(candidates: [candidate], completionStatus: .complete),
                for: request
            )
        )
    }

    func testDecomposeTopicWhitelistStillRejectsUnknownTopic() throws {
        let sourceID = UUID()
        let chunkID = UUID()
        let request = DecomposeRequest(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            markdown: "kafka",
            ownedStartOffset: 0,
            ownedEndOffset: 5,
            availableTopicNames: ["redis"]
        )
        let anchor = SourceAnchor(
            sourceDocumentID: sourceID,
            chunkID: chunkID,
            startOffset: 0,
            endOffset: 5,
            exactQuote: "kafka"
        )
        let candidate = CandidateDraft(
            id: UUID(),
            ordinal: 0,
            question: "Kafka 的消费者组如何工作？",
            sourceBackedAnswerMaterial: "kafka",
            sourceAnchors: [anchor],
            topicName: "kafka"
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                .init(candidates: [candidate], completionStatus: .complete),
                for: request
            )
        ) { error in
            XCTAssertEqual(error as? AIResponseValidationError, .unknownTopic("kafka"))
        }
    }

    func testRefineAllowedTopicsIgnoreInvisibleSpacing() throws {
        let sourceID = UUID()
        let chunkID = UUID()
        let candidateID = UUID()
        let card = RefinedCardDraft(
            id: UUID(),
            mergedCandidateIDs: [candidateID],
            question: "如何设计一个短链接系统？",
            fullScoreAnswer: "短链接系统需要考虑哈希、冲突和缓存。",
            topicName: "system design",
            sourceAnchors: [
                SourceAnchor(
                    sourceDocumentID: sourceID,
                    chunkID: chunkID,
                    startOffset: 0,
                    endOffset: 6,
                    exactQuote: "system"
                )
            ]
        )

        XCTAssertNoThrow(
            try AIResponseValidator.validate(
                .init(cards: [card], completionStatus: .complete),
                allowedTopics: ["system\u{2006}design"]
            )
        )
    }

    func testReclassifyWhitelistIgnoresInvisibleSpacing() throws {
        let cardID = UUID()
        let response = ReclassifyResponse(
            assignments: [.init(cardID: cardID, topicName: "system design")],
            completionStatus: .complete
        )
        let request = ReclassifyRequest(
            batchID: UUID(),
            cards: [.init(id: cardID, question: "问题", fullScoreAnswer: "答案")],
            availableTopicNames: ["system\u{2006}design"]
        )

        XCTAssertNoThrow(
            try AIResponseValidator.validate(response, for: request)
        )
    }

    func testClientComputesFixedWeightedTotalAsSeventyFive() throws {
        let dimensions = makeDimensions()
        XCTAssertEqual(EvaluationRubric.general.total(for: dimensions), 75)
        XCTAssertEqual(
            ScoringRubric.general.total(
                for: DimensionScores(
                    correctness: 80,
                    coverage: 60,
                    reasoning: 80,
                    structure: 80,
                    tradeoffs: 70,
                    precision: 100
                )
            ),
            75
        )
    }

    func testEvaluationDecodingNormalizesProviderRubricAliases() throws {
        let payload = """
        {
          "scorable": true,
          "notScorableReason": "",
          "dimensions": [
            {"key":"accuracy","score":95,"evidence":[{"quote":"raw fragment","explanation":"准确"}],"missedPoints":["补充边界"],"feedback":"准确"},
            {"key":"completeness","score":86,"evidence":[{"quote":"raw fragment","explanation":"覆盖"}],"missedPoints":["补充边界"],"feedback":"覆盖"},
            {"key":"clarity","score":78,"evidence":[{"quote":"raw fragment","explanation":"清晰"}],"missedPoints":["补充边界"],"feedback":"清晰"},
            {"key":"technicalDepth","score":90,"evidence":[{"quote":"raw fragment","explanation":"深入"}],"missedPoints":["补充边界"],"feedback":"深入"},
            {"key":"conciseness","score":95,"evidence":[{"quote":"raw fragment","explanation":"简洁"}],"missedPoints":["补充边界"],"feedback":"简洁"},
            {"key":"codeCorrectness","score":88,"evidence":[{"quote":"raw fragment","explanation":"实现"}],"missedPoints":["补充边界"],"feedback":"实现"}
          ],
          "factualErrors": [],
          "strengths": ["核心结论正确"],
          "gapsAndErrors": ["补充边界"],
          "improvements": ["补充边界"],
          "polishOnlyClaims": [],
          "confidence": 90,
          "scoreRange": {"low": 80, "high": 95},
          "warnings": [],
          "modelID": "deepseek-v4-flash",
          "promptVersion": "evaluate-senior-v3",
          "rubricVersion": "senior-software-engineer-v2",
          "completionStatus": "complete"
        }
        """

        let response = try JSONDecoder().decode(
            EvaluationResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(response.notScorableReason)
        XCTAssertEqual(response.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(
            response.dimensions.map(\.key),
            [.correctness, .coverage, .structure, .reasoning, .precision, .tradeoffs]
        )
        try AIResponseValidator.validate(
            response,
            rubric: EvaluationRubric.seniorSoftwareEngineer,
            rawText: "raw fragment",
            polishedText: "raw fragment"
        )
    }

    func testScoreDecodingNormalizesDeepSeekCompactRubric() throws {
        let payload = """
        {
          "scorable": true,
          "notScorableReason": null,
          "dimensions": [
            {"key":"technical_accuracy","score":4},
            {"key":"depth_of_knowledge","score":3},
            {"key":"clarity_of_expression","score":4},
            {"key":"problem_solving","score":3},
            {"key":"practical_application","score":3},
            {"key":"innovation_and_insight","score":2}
          ],
          "confidence": 0.9,
          "scoreRange": {"min": 3, "max": 4},
          "warnings": [],
          "modelID": "gpt-4-2024-06-01",
          "promptVersion": "evaluate-score-v1",
          "rubricVersion": "senior-software-engineer-v2",
          "completionStatus": "completed"
        }
        """

        let response = try JSONDecoder().decode(
            EvaluationScoreResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(response.completionStatus, .complete)
        XCTAssertEqual(response.scoreRange, .init(low: 60, high: 80))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: response.dimensions.map { ($0.key, $0.score) }),
            [
                .correctness: 80,
                .coverage: 60,
                .reasoning: 60,
                .structure: 80,
                .tradeoffs: 60,
                .precision: 40,
            ]
        )
        try AIResponseValidator.validate(
            response,
            rubric: .seniorSoftwareEngineer
        )
    }

    func testFeedbackDecodingNormalizesDeepSeekScalarEvidenceAndMissedPoints() throws {
        let payload = """
        {
          "dimensions": [
            {"key":"correctness","evidence":"Kafka 通过顺序写、页缓存、批量和压缩提高吞吐","missedPoints":"未解释网络路径","feedback":"核心机制判断正确，但解释不够具体。"},
            {"key":"coverage","evidence":"Kafka 通过顺序写、页缓存、批量和压缩提高吞吐","missedPoints":"遗漏网络路径","feedback":"覆盖了部分考点。"},
            {"key":"reasoning","evidence":"Kafka 通过顺序写、页缓存、批量和压缩提高吞吐","missedPoints":"缺少因果解释","feedback":"没有展开机制。"},
            {"key":"structure","evidence":"Kafka 通过顺序写、页缓存、批量和压缩提高吞吐","missedPoints":"未逐层组织","feedback":"结构仍然概括。"},
            {"key":"tradeoffs","evidence":"代价是分区规划和一致性需要权衡","missedPoints":"未展开权衡","feedback":"提到了取舍但没有解释。"},
            {"key":"precision","evidence":"Kafka 通过顺序写、页缓存、批量和压缩提高吞吐","missedPoints":"缺少细节","feedback":"表述过于笼统。"}
          ],
          "factualErrors": [],
          "strengths": ["识别了主要机制"],
          "gapsAndErrors": ["遗漏网络路径"],
          "improvements": ["逐层解释性能机制"],
          "polishOnlyClaims": [],
          "confidence": 0.9,
          "scoreRange": [30, 60],
          "warnings": [],
          "modelID": "gpt-4o",
          "promptVersion": "evaluate-feedback-v1",
          "rubricVersion": "senior-software-engineer-v2",
          "completionStatus": "complete"
        }
        """

        let response = try JSONDecoder().decode(
            EvaluationFeedbackResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(response.dimensions.count, 6)
        XCTAssertEqual(response.dimensions[0].evidence.first?.quote, "Kafka 通过顺序写、页缓存、批量和压缩提高吞吐")
        XCTAssertEqual(response.dimensions[0].missedPoints, ["未解释网络路径"])
        try AIResponseValidator.validate(
            response,
            scores: [
                .init(key: .correctness, score: 60),
                .init(key: .coverage, score: 30),
                .init(key: .reasoning, score: 30),
                .init(key: .structure, score: 40),
                .init(key: .tradeoffs, score: 30),
                .init(key: .precision, score: 60),
            ],
            rubric: .seniorSoftwareEngineer,
            rawText: "Kafka 通过顺序写、页缓存、批量和压缩提高吞吐，并用副本与 ISR 提供容错；代价是分区规划和一致性需要权衡。"
        )
    }

    func testFeedbackDecodingNormalizesStringListsAndStringScoreRange() throws {
        let payload = """
        {
          "dimensions": [
            {"key":"correctness","evidence":"存活 准备好接受流量 心跳","missedPoints":"未说明 liveness 失败重启","feedback":"回答过于简略。"},
            {"key":"coverage","evidence":"存活 准备好接受流量 心跳","missedPoints":"未区分三种探针","feedback":"覆盖不足。"},
            {"key":"reasoning","evidence":"存活 准备好接受流量 心跳","missedPoints":"未解释级联故障","feedback":"缺少机制解释。"},
            {"key":"structure","evidence":"存活 准备好接受流量 心跳","missedPoints":"没有结构","feedback":"需要按定义-区别组织。"},
            {"key":"tradeoffs","evidence":"存活 准备好接受流量 心跳","missedPoints":"未讲取舍","feedback":"缺少工程权衡。"},
            {"key":"precision","evidence":"存活 准备好接受流量 心跳","missedPoints":"术语不准确","feedback":"表述模糊。"}
          ],
          "factualErrors": ["没有指出 liveness 失败会重启容器"],
          "strengths": "识别了关键词",
          "gapsAndErrors": "未区分三种探针",
          "improvements": "补充每个探针的核心机制",
          "polishOnlyClaims": "",
          "confidence": 0.9,
          "scoreRange": "49-64",
          "warnings": "回答过短",
          "modelID": "deepseek-v4-flash",
          "promptVersion": "evaluate-feedback-v1",
          "rubricVersion": "senior-software-engineer-v2",
          "completionStatus": "complete"
        }
        """

        let response = try JSONDecoder().decode(
            EvaluationFeedbackResponse.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(response.dimensions.count, 6)
        XCTAssertEqual(response.factualErrors.count, 1)
        XCTAssertEqual(response.factualErrors[0].statement, "没有指出 liveness 失败会重启容器")
        XCTAssertEqual(response.strengths, ["识别了关键词"])
        XCTAssertEqual(response.gapsAndErrors, ["未区分三种探针"])
        XCTAssertEqual(response.improvements, ["补充每个探针的核心机制"])
        XCTAssertEqual(response.warnings, ["回答过短"])
        XCTAssertEqual(response.scoreRange.low, 49)
        XCTAssertEqual(response.scoreRange.high, 64)
    }

    func testSeniorEvaluationRejectsVersionMismatchAndUnsupportedEvidence() throws {
        let response = makeEvaluation(
            rubric: .seniorSoftwareEngineer,
            promptVersion: "wrong-prompt"
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: .seniorSoftwareEngineer,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个"
            )
        )

        let unsupported = makeEvaluation(
            dimensions: makeDimensions(rubric: .seniorSoftwareEngineer).map { dimension in
                guard dimension.key == .correctness else { return dimension }
                return EvaluationDimension(
                    key: dimension.key,
                    score: dimension.score,
                    evidence: [.init(quote: "模型编造的句子", explanation: "看似像证据")],
                    missedPoints: dimension.missedPoints,
                    feedback: dimension.feedback
                )
            }
        )
        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                unsupported,
                rubric: .seniorSoftwareEngineer,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个"
            )
        )
    }

    func testSeniorEvaluationRequiresSpecificFeedbackEvidenceAndMissedPoints() throws {
        var dimensions = makeDimensions(rubric: .seniorSoftwareEngineer)
        dimensions[0] = EvaluationDimension(
            key: .correctness,
            score: 80,
            evidence: [.init(quote: "CAP", explanation: "")],
            missedPoints: [],
            feedback: ""
        )
        let response = makeEvaluation(
            dimensions: dimensions,
            rubric: .seniorSoftwareEngineer,
            gapsAndErrors: [],
            improvements: []
        )

        XCTAssertThrowsError(
            try AIResponseValidator.validate(
                response,
                rubric: .seniorSoftwareEngineer,
                rawText: "CAP 只能同时满足两个",
                polishedText: "CAP 只能同时满足两个"
            )
        )
    }

    private func makeDimensions(rubric: EvaluationRubric = .general) -> [EvaluationDimension] {
        let scores: [(ScoreDimension, Int)] = [
            (.correctness, 80),
            (.coverage, 60),
            (.reasoning, 80),
            (.structure, 80),
            (.tradeoffs, 70),
            (.precision, 100)
        ]
        return scores.map { key, score in
            EvaluationDimension(
                key: key,
                score: score,
                evidence: [.init(quote: "CAP", explanation: "原文证据")],
                missedPoints: score == 100 ? [] : ["补充一个边界条件"],
                feedback: "测试反馈"
            )
        }
    }

    private func makeEvaluation(
        dimensions: [EvaluationDimension]? = nil,
        rubric: EvaluationRubric = .general,
        promptVersion: String? = nil,
        gapsAndErrors: [String] = ["缺少边界"],
        improvements: [String] = ["补充边界"]
    ) -> EvaluationResponse {
        EvaluationResponse(
            scorable: true,
            notScorableReason: nil,
            dimensions: dimensions ?? makeDimensions(rubric: rubric),
            factualErrors: [],
            strengths: ["有核心结论"],
            gapsAndErrors: gapsAndErrors,
            improvements: improvements,
            polishOnlyClaims: [],
            confidence: 0.9,
            scoreRange: .init(low: 70, high: 80),
            warnings: [],
            modelID: "test-model",
            promptVersion: promptVersion ?? PromptCatalog.evaluateVersion,
            rubricVersion: rubric.version,
            completionStatus: .complete
        )
    }
}
