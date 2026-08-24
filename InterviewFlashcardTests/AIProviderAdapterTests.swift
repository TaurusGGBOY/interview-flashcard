import Foundation
import XCTest

final class AIProviderAdapterTests: XCTestCase {
    func testOpenAIResponsesRequestAndResponse() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(adapter: adapter, provider: .openAI, mode: .structuredJSON)
        let body = try jsonBody(request)
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let text = try XCTUnwrap(body["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-marker")
        XCTAssertEqual(body["model"] as? String, "gpt-5.6-terra")
        XCTAssertEqual(input.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "interview_flashcard_response")
        XCTAssertEqual(format["strict"] as? Bool, false)
        XCTAssertEqual((format["schema"] as? [String: Any])?["type"] as? String, "object")
        XCTAssertFalse(try bodyString(request).contains("secret-marker"))

        let data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"你好，OpenAI"}]}]}"#.utf8)
        XCTAssertEqual(
            try adapter.responseText(from: data, response: response(for: request, status: 200)),
            "你好，OpenAI"
        )
    }

    func testOpenAIResponsesAcceptsTopLevelOutputTextFromCompatibleGateway() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(adapter: adapter, provider: .openAI)
        let data = Data(#"{"output_text":"{\"scorable\":true}"}"#.utf8)

        XCTAssertEqual(
            try adapter.responseText(from: data, response: response(for: request, status: 200)),
            "{\"scorable\":true}"
        )
    }

    func testOpenAIResponsesAcceptsChatCompatibleChoicesFromGateway() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(adapter: adapter, provider: .openAI)
        let data = Data(#"{"choices":[{"message":{"content":"{\"scorable\":true}"}}]}"#.utf8)

        XCTAssertEqual(
            try adapter.responseText(from: data, response: response(for: request, status: 200)),
            "{\"scorable\":true}"
        )
    }

    func testOpenAIResponsesAcceptsValueFieldFromCompatibleGateway() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(adapter: adapter, provider: .openAI)
        let data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","value":"{\"scorable\":true}"}]}]}"#.utf8)

        XCTAssertEqual(
            try adapter.responseText(from: data, response: response(for: request, status: 200)),
            "{\"scorable\":true}"
        )
    }

    func testOpenAIPlainTextRequestOmitsStructuredFormat() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(adapter: adapter, provider: .openAI, mode: .plainText)

        XCTAssertNil(try jsonBody(request)["text"])
    }

    func testOpenAICompatibleChatRequestAndResponse() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAICompatible)
        let request = try makeRequest(
            adapter: adapter,
            provider: .openAICompatible,
            mode: .structuredJSON
        )
        let body = try jsonBody(request)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-marker")
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        XCTAssertEqual(schema["name"] as? String, "interview_flashcard_response")
        XCTAssertEqual(schema["strict"] as? Bool, false)
        XCTAssertFalse(try bodyString(request).contains("secret-marker"))

        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"你好，兼容服务"},"finish_reason":"stop"}]}"#.utf8)
        XCTAssertEqual(
            try adapter.responseText(from: data, response: response(for: request, status: 200)),
            "你好，兼容服务"
        )
    }

    func testEvaluationFeedbackSchemaRequiresAllDetailedFields() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAICompatible)
        let request = try makeRequest(
            adapter: adapter,
            provider: .openAICompatible,
            responseSchema: .evaluationFeedback
        )
        let body = try jsonBody(request)
        let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
        let schema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
        let objectSchema = try XCTUnwrap(schema["schema"] as? [String: Any])
        let properties = try XCTUnwrap(objectSchema["properties"] as? [String: Any])
        let required = try XCTUnwrap(objectSchema["required"] as? [String])

        XCTAssertTrue(properties.keys.contains("dimensions"))
        XCTAssertTrue(properties.keys.contains("scoreRange"))
        XCTAssertTrue(properties.keys.contains("completionStatus"))
        XCTAssertEqual(Set(required), Set(properties.keys))
    }

    func testEveryProductionStructuredSchemaHasRequiredTopLevelFields() throws {
        for schemaKind in AIResponseSchema.allCases where schemaKind != .generic {
            let adapter = AIProviderAdapterFactory.make(for: .openAICompatible)
            let request = try makeRequest(
                adapter: adapter,
                provider: .openAICompatible,
                responseSchema: schemaKind
            )
            let body = try jsonBody(request)
            let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
            let schema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
            let objectSchema = try XCTUnwrap(schema["schema"] as? [String: Any])
            let required = try XCTUnwrap(objectSchema["required"] as? [String])
            XCTAssertFalse(required.isEmpty, "(schemaKind) must require top-level fields")
        }
    }

    func testDeepSeekCanUseNonThinkingModeForFastScoreStage() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAICompatible)
        let request = try makeRequest(
            adapter: adapter,
            provider: .openAICompatible,
            thinking: .disabled
        )
        let body = try jsonBody(request)
        let thinking = try XCTUnwrap(body["thinking"] as? [String: Any])

        XCTAssertEqual(thinking["type"] as? String, "disabled")
    }

    func testOpenAIResponsesDisablesReasoningForDeepSeek() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(
            adapter: adapter,
            provider: .openAI,
            thinking: .disabled
        )
        let reasoning = try XCTUnwrap(try jsonBody(request)["reasoning"] as? [String: Any])

        XCTAssertEqual(reasoning["effort"] as? String, "none")

        let defaultRequest = try makeRequest(adapter: adapter, provider: .openAI)
        XCTAssertNil(try jsonBody(defaultRequest)["reasoning"])
    }

    func testOpenAICompatibleLengthFinishIsTruncated() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAICompatible)
        let request = try makeRequest(adapter: adapter, provider: .openAICompatible)
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"partial"},"finish_reason":"length"}]}"#.utf8)

        XCTAssertThrowsError(
            try adapter.responseText(from: data, response: response(for: request, status: 200))
        ) { error in
            XCTAssertEqual(error as? AIError, .truncatedResponse)
        }
    }

    func testAnthropicMessagesRequestAndResponse() throws {
        let adapter = AIProviderAdapterFactory.make(for: .anthropic)
        let request = try makeRequest(adapter: adapter, provider: .anthropic, mode: .structuredJSON)
        let body = try jsonBody(request)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret-marker")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "anthropic-version"),
            "2023-06-01"
        )
        XCTAssertEqual(body["system"] as? String, "system-instruction")
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "user-message")
        XCTAssertEqual(body["max_tokens"] as? Int, 8_192)
        XCTAssertNil(body["temperature"])
        XCTAssertFalse(try bodyString(request).contains("secret-marker"))

        let data = Data(#"{"content":[{"type":"text","text":"你好，Anthropic"}],"stop_reason":"end_turn"}"#.utf8)
        XCTAssertEqual(
            try adapter.responseText(from: data, response: response(for: request, status: 200)),
            "你好，Anthropic"
        )
    }

    func testAnthropicPlainTextUsesSmallOutputBudgetAndMaxTokensIsTruncated() throws {
        let adapter = AIProviderAdapterFactory.make(for: .anthropic)
        let request = try makeRequest(adapter: adapter, provider: .anthropic, mode: .plainText)
        XCTAssertEqual(try jsonBody(request)["max_tokens"] as? Int, 256)

        let data = Data(#"{"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}"#.utf8)
        XCTAssertThrowsError(
            try adapter.responseText(from: data, response: response(for: request, status: 200))
        ) { error in
            XCTAssertEqual(error as? AIError, .truncatedResponse)
        }
    }

    func testHTTPStatusMappingIsConsistentAcrossProviders() throws {
        for provider in AIProviderKind.allCases {
            let adapter = AIProviderAdapterFactory.make(for: provider)
            let request = try makeRequest(adapter: adapter, provider: provider)
            let empty = Data()

            assertError(.unauthorized) {
                try adapter.responseText(from: empty, response: response(for: request, status: 401))
            }
            assertError(.rateLimited) {
                try adapter.responseText(from: empty, response: response(for: request, status: 429))
            }
            assertError(.transientHTTPStatus(503)) {
                try adapter.responseText(from: empty, response: response(for: request, status: 503))
            }
            assertError(.httpStatus(400)) {
                try adapter.responseText(from: empty, response: response(for: request, status: 400))
            }
        }
    }

    func testMalformedSuccessResponseDoesNotExposeBody() throws {
        let adapter = AIProviderAdapterFactory.make(for: .openAI)
        let request = try makeRequest(adapter: adapter, provider: .openAI)
        let secretBody = Data(#"{"secret":"must-not-leak"}"#.utf8)

        XCTAssertThrowsError(
            try adapter.responseText(
                from: secretBody,
                response: response(for: request, status: 200)
            )
        ) { error in
            let message = String(describing: error)
            XCTAssertFalse(message.contains("must-not-leak"))
        }
    }

    private func makeRequest(
        adapter: any AIProviderAdapter,
        provider: AIProviderKind,
        mode: AIProviderResponseMode = .structuredJSON,
        responseSchema: AIResponseSchema = .generic,
        thinking: AIThinkingMode? = nil
    ) throws -> URLRequest {
        try adapter.makeRequest(
            configuration: provider.defaultConfiguration,
            apiKey: "secret-marker",
            systemPrompt: "system-instruction",
            userMessage: "user-message",
            mode: mode,
            responseSchema: responseSchema,
            timeout: 30,
            maxOutputTokens: nil,
            thinking: thinking
        )
    }

    private func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func bodyString(_ request: URLRequest) throws -> String {
        try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
    }

    private func assertError(
        _ expected: AIError,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation()) { error in
            XCTAssertEqual(error as? AIError, expected)
        }
    }
}
