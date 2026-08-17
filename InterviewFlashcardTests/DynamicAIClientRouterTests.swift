import Foundation
import XCTest

final class DynamicAIClientRouterTests: XCTestCase {
    func testNextRequestImmediatelyUsesReplacementConfigurationAndKey() async throws {
        let configurationStore = InMemoryAIConfigurationStore(
            configuration: .init(
                provider: .openAICompatible,
                baseURL: "https://first.example.com/v1",
                model: "first-model"
            )
        )
        let keyStore = InMemoryAPIKeyStore(key: "first-key")
        let transport = ProviderRoutingTransport()
        let client = DynamicAIClientRouter(
            configurationStore: configurationStore,
            apiKeyStore: keyStore,
            transport: transport
        )

        _ = try await client.polish(request)
        configurationStore.save(.init(
            provider: .anthropic,
            baseURL: "https://second.example.com/gateway/v1",
            model: "second-model"
        ))
        try keyStore.save("second-key")
        _ = try await client.polish(request)

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://first.example.com/v1/chat/completions",
            "https://second.example.com/gateway/v1/messages",
        ])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer first-key")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-api-key"), "second-key")
    }

    func testRequestKeepsEntrySnapshotWhenStoresChangeInsideTransport() async throws {
        let configurationStore = InMemoryAIConfigurationStore(
            configuration: .init(
                provider: .openAI,
                baseURL: "https://snapshot.example.com",
                model: "snapshot-model"
            )
        )
        let keyStore = InMemoryAPIKeyStore(key: "snapshot-key")
        let transport = ProviderRoutingTransport {
            configurationStore.save(.init(
                provider: .anthropic,
                baseURL: "https://changed.example.com",
                model: "changed-model"
            ))
            try? keyStore.save("changed-key")
        }
        let client = DynamicAIClientRouter(
            configurationStore: configurationStore,
            apiKeyStore: keyStore,
            transport: transport
        )

        _ = try await client.polish(request)

        let capturedRequests = await transport.requests
        let captured = try XCTUnwrap(capturedRequests.first)
        XCTAssertEqual(captured.url?.absoluteString, "https://snapshot.example.com/v1/responses")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Authorization"), "Bearer snapshot-key")
    }

    func testMissingKeyStopsBeforeTransport() async {
        let transport = ProviderRoutingTransport()
        let client = DynamicAIClientRouter(
            configurationStore: InMemoryAIConfigurationStore(),
            apiKeyStore: InMemoryAPIKeyStore(),
            transport: transport
        )

        do {
            _ = try await client.polish(request)
            XCTFail("Expected missing API key")
        } catch {
            XCTAssertEqual(error as? AIError, .missingAPIKey)
        }
        let capturedRequests = await transport.requests
        XCTAssertTrue(capturedRequests.isEmpty)
    }

    private var request: PolishRequest {
        PolishRequest(rawText: "本地回答", localeIdentifier: "zh-CN")
    }
}

private actor ProviderRoutingTransport: AIHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let onRequest: @Sendable () -> Void

    init(onRequest: @escaping @Sendable () -> Void = {}) {
        self.onRequest = onRequest
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        onRequest()
        let structured = #"{"polishedText":"本地回答","edits":[],"suspectedTranscriptionIssues":[],"introducedClaims":[],"needsUserReview":false,"warnings":[],"modelID":"provider-model","promptVersion":"polish-v1","completionStatus":"complete"}"#
        let envelope: [String: Any]
        switch request.url?.lastPathComponent {
        case "responses":
            envelope = [
                "output": [[
                    "type": "message",
                    "content": [["type": "output_text", "text": structured]],
                ]],
            ]
        case "messages":
            envelope = [
                "content": [["type": "text", "text": structured]],
                "stop_reason": "end_turn",
            ]
        default:
            envelope = [
                "choices": [[
                    "message": ["role": "assistant", "content": structured],
                    "finish_reason": "stop",
                ]],
            ]
        }
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
