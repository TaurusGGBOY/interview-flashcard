import Foundation
import XCTest

final class ConfiguredAIClientTests: XCTestCase {
    func testQuestionGenerationPromptPrintsExactTopicWhitelistAndRequiresTopicName() {
        let prompt = PromptCatalog.systemPrompt(
            for: .decompose,
            availableTopicNames: ["K8S", "Others"]
        )

        XCTAssertTrue(prompt.contains("[\"K8S\", \"Others\"]"))
        XCTAssertTrue(prompt.contains("topicName"))
        XCTAssertTrue(prompt.contains("只能原样复制"))
        XCTAssertTrue(prompt.contains("Every returned question MUST be a complete, standalone question"))
        XCTAssertTrue(prompt.contains("Do not leave references such as “上述方案”“这个问题”“它”“该组件” unresolved"))
    }

    func testEvaluationScorePromptDefinesScoreRangeObject() {
        let prompt = PromptCatalog.systemPrompt(for: .evaluateScore)

        XCTAssertTrue(prompt.contains("scoreRange MUST be an object with integer low and integer high fields"))
        XCTAssertTrue(prompt.contains("low less than or equal to high"))
    }

    func testReclassifyPromptDefinesAssignmentJSONShape() {
        let prompt = PromptCatalog.systemPrompt(
            for: .reclassify,
            availableTopicNames: ["K8S", "Others"]
        )

        XCTAssertTrue(prompt.contains("assignments (array) and completionStatus"))
        XCTAssertTrue(prompt.contains("cardID"))
        XCTAssertTrue(prompt.contains("topicName"))
        XCTAssertTrue(prompt.contains("one assignment"))
    }

    func testEvaluationFeedbackRepairsUngroundedSpeechTranscriptEvidence() async throws {
        let rawText = "在Clock code里面的话，只agent的上下文之间的传递，主要通过Mell box这样的机制。"
        let dimensions = ScoreDimension.allCases.map { dimension in
            [
                "key": dimension.rawValue,
                "evidence": [[
                    "quote": "The rawText mentions a mailbox-based message passing pattern.",
                    "explanation": "模型对口语转写内容做了归纳。",
                ]],
                "missedPoints": ["补充边界条件。"],
                "feedback": "需要补充具体机制。",
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "dimensions": dimensions,
            "factualErrors": [],
            "strengths": ["指出了消息传递方向。"],
            "gapsAndErrors": ["缺少边界条件。"],
            "improvements": ["补充失败处理。"],
            "polishOnlyClaims": [],
            "confidence": 0.8,
            "scoreRange": ["low": 0, "high": 100],
            "warnings": [],
            "modelID": "mimo-v2.5",
            "promptVersion": PromptCatalog.evaluateFeedbackVersion,
            "rubricVersion": EvaluationRubric.seniorSoftwareEngineer.version,
            "completionStatus": "complete",
        ]
        let content = String(
            data: try JSONSerialization.data(withJSONObject: payload),
            encoding: .utf8
        )!
        let client = ConfiguredAIClient(
            configuration: .init(
                provider: .openAI,
                baseURL: "https://opencode.ai/zen/go",
                model: "mimo-v2.5"
            ),
            apiKey: "test-key",
            transport: CapturingDecomposeTransport(content: content)
        )

        let scores = ScoreDimension.allCases.map {
            EvaluationScoreDimension(key: $0, score: 50)
        }
        let response = try await client.evaluationFeedback(
            EvaluationFeedbackRequest(
                question: "Clock code 如何传递上下文？",
                referenceAnswer: "",
                sourceBackedMaterial: "",
                rawText: rawText,
                scores: scores
            )
        )

        XCTAssertEqual(response.dimensions.count, 6)
        XCTAssertEqual(response.dimensions.first?.evidence.first?.quote, rawText)
    }

    func testDecomposeAllowsLongRunningProviderResponse() async throws {
        let transport = CapturingDecomposeTransport()
        let client = ConfiguredAIClient(
            configuration: .init(
                provider: .openAI,
                baseURL: "https://opencode.ai/zen/go",
                model: "deepseek-v4-flash"
            ),
            apiKey: "test-key",
            transport: transport
        )

        _ = try await client.decompose(
            DecomposeRequest(
                sourceDocumentID: UUID(),
                chunkID: UUID(),
                markdown: "## Q01\n\nCAP theorem",
                ownedStartOffset: 0,
                ownedEndOffset: 22
            )
        )

        let capturedRequest = await transport.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.timeoutInterval, 600)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["max_output_tokens"] as? Int, 8192)
        let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "none")
    }

    func testDecomposeAcceptsProviderMetadataThatCoordinatorCanCanonicalize() async throws {
        let transport = CapturingDecomposeTransport(content: #"""
            {
                "candidates": [{
                "id": "candidate-1",
                "ordinal": 0,
                "question": "CAP theorem",
                "answer": "Consistency, availability, and partition tolerance are tradeoffs.",
                "sourceAnchors": [{
                    "sourceDocumentId": "provider-document-id",
                    "chunkId": "provider-chunk-id",
                    "start": 0,
                    "end": 0,
                    "quote": "CAP theorem"
                }]
                }],
                "completionStatus": "completed"
            }
        """#)
        let client = ConfiguredAIClient(
            configuration: .init(
                provider: .openAI,
                baseURL: "https://opencode.ai/zen/go",
                model: "deepseek-v4-flash"
            ),
            apiKey: "test-key",
            transport: transport
        )

        let response = try await client.decompose(
            DecomposeRequest(
                sourceDocumentID: UUID(),
                chunkID: UUID(),
                markdown: "## Q01\n\nCAP theorem",
                ownedStartOffset: 0,
                ownedEndOffset: 22
            )
        )

        let candidate = try XCTUnwrap(response.candidates.first)
        XCTAssertNotEqual(candidate.id.uuidString.lowercased(), "candidate-1")
        XCTAssertEqual(candidate.sourceBackedAnswerMaterial, "Consistency, availability, and partition tolerance are tradeoffs.")
        XCTAssertEqual(candidate.sourceAnchors.first?.exactQuote, "CAP theorem")
    }
}

private actor CapturingDecomposeTransport: AIHTTPTransport {
    private(set) var request: URLRequest?
    private let content: String

    init(content: String = #"{"candidates":[],"completionStatus":"complete"}"#) {
        self.content = content
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let envelope: [String: Any] = [
            "output": [[
                "type": "message",
                "content": [["type": "output_text", "text": content]],
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}
