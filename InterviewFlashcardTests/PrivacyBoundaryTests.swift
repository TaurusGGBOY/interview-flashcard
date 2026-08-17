import Foundation
import XCTest

final class PrivacyBoundaryTests: XCTestCase {
    func testDeepSeekRequestDoesNotPutAPIKeyOrAudioInJSONPayload() async throws {
        let transport = RecordingAITransport()
        let store = InMemoryAPIKeyStore(key: "secret-marker")
        let client = DeepSeekAIClient(
            configuration: .init(model: "configured-model"),
            apiKeyStore: store,
            transport: transport
        )

        let response = try await client.polish(
            PolishRequest(
                rawText: "本地回答",
                localeIdentifier: "zh-CN"
            )
        )
        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertEqual(response.modelID, "privacy-test-model")
        XCTAssertFalse(body.contains("secret-marker"))
        XCTAssertFalse(body.localizedCaseInsensitiveContains(".m4a"))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret-marker"
        )
    }
}

private actor RecordingAITransport: AIHTTPTransport {
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let content = """
        {"polishedText":"本地回答","edits":[],"suspectedTranscriptionIssues":[],"introducedClaims":[],"needsUserReview":false,"warnings":[],"modelID":"privacy-test-model","promptVersion":"polish-v1","completionStatus":"complete"}
        """
        let envelope = Envelope(output: [
            .init(
                type: "message",
                content: [.init(type: "output_text", text: content)]
            ),
        ])
        let data = try JSONEncoder().encode(envelope)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    private struct Envelope: Encodable {
        let output: [Output]

        struct Output: Encodable {
            let type: String
            let content: [Content]
        }

        struct Content: Encodable {
            let type: String
            let text: String
        }
    }
}
