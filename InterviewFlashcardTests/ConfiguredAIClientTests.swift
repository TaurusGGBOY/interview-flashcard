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
