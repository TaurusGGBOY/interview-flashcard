import Foundation
import XCTest

final class AIConnectionTesterTests: XCTestCase {
    func testEachProviderUsesDraftAndSendsHelloWithoutStores() async throws {
        for provider in AIProviderKind.allCases {
            let transport = ConnectionTestTransport()
            let tester = AIConnectionTester(transport: transport)
            var configuration = provider.defaultConfiguration
            configuration.baseURL = "https://draft.example.com/prefix"
            configuration.model = "draft-model"

            let reply = try await tester.test(
                configuration: configuration,
                apiKey: "draft-key"
            )

            XCTAssertEqual(reply, "你好，连接正常")
            let capturedRequest = await transport.request
            let request = try XCTUnwrap(capturedRequest)
            XCTAssertEqual(request.timeoutInterval, 30)
            XCTAssertTrue(try requestContainsHello(request))
            XCTAssertTrue(try requestContainsModel("draft-model", request: request))
            XCTAssertFalse(try bodyString(request).contains("draft-key"))
        }
    }

    func testConnectionTestRejectsEmptyDraftKeyBeforeTransport() async {
        let transport = ConnectionTestTransport()
        let tester = AIConnectionTester(transport: transport)

        do {
            _ = try await tester.test(
                configuration: AIProviderKind.openAI.defaultConfiguration,
                apiKey: " \n"
            )
            XCTFail("Expected missing key")
        } catch {
            XCTAssertEqual(error as? AIError, .missingAPIKey)
        }
        let capturedRequest = await transport.request
        XCTAssertNil(capturedRequest)
    }

    func testConnectionTestPropagatesSafeProviderError() async {
        let transport = ConnectionTestTransport(status: 401)
        let tester = AIConnectionTester(transport: transport)

        do {
            _ = try await tester.test(
                configuration: AIProviderKind.anthropic.defaultConfiguration,
                apiKey: "secret-do-not-leak"
            )
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? AIError, .unauthorized)
            XCTAssertFalse(String(describing: error).contains("secret-do-not-leak"))
        }
    }

    private func requestContainsHello(_ request: URLRequest) throws -> Bool {
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))
        return containsHello(object)
    }

    private func containsHello(_ value: Any) -> Bool {
        if let value = value as? String {
            return value == "你好"
        }
        if let values = value as? [Any] {
            return values.contains(where: containsHello)
        }
        if let values = value as? [String: Any] {
            return values.values.contains(where: containsHello)
        }
        return false
    }

    private func requestContainsModel(_ model: String, request: URLRequest) throws -> Bool {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        return object["model"] as? String == model
    }

    private func bodyString(_ request: URLRequest) throws -> String {
        try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
    }
}

private actor ConnectionTestTransport: AIHTTPTransport {
    private(set) var request: URLRequest?
    private let status: Int

    init(status: Int = 200) {
        self.status = status
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        guard status == 200 else { return (Data(), response) }

        let data: Data
        switch request.url?.lastPathComponent {
        case "responses":
            data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"你好，连接正常"}]}]}"#.utf8)
        case "messages":
            data = Data(#"{"content":[{"type":"text","text":"你好，连接正常"}],"stop_reason":"end_turn"}"#.utf8)
        default:
            data = Data(#"{"choices":[{"message":{"role":"assistant","content":"你好，连接正常"},"finish_reason":"stop"}]}"#.utf8)
        }
        return (data, response)
    }
}
