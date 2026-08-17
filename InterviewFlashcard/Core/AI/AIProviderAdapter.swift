import Foundation

enum AIProviderResponseMode: Equatable, Sendable {
    case structuredJSON
    case plainText
}

enum AIThinkingMode: String, Equatable, Sendable {
    case enabled
    case disabled
}

protocol AIProviderAdapter: Sendable {
    func makeRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        mode: AIProviderResponseMode,
        timeout: TimeInterval,
        maxOutputTokens: Int?,
        thinking: AIThinkingMode?
    ) throws -> URLRequest

    func responseText(from data: Data, response: HTTPURLResponse) throws -> String
}

enum AIProviderAdapterFactory {
    static func make(for provider: AIProviderKind) -> any AIProviderAdapter {
        switch provider {
        case .openAI: OpenAIResponsesAdapter()
        case .openAICompatible: OpenAICompatibleChatAdapter()
        case .anthropic: AnthropicMessagesAdapter()
        }
    }
}

private struct OpenAIResponsesAdapter: AIProviderAdapter {
    func makeRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        mode: AIProviderResponseMode,
        timeout: TimeInterval,
        maxOutputTokens: Int?,
        thinking: AIThinkingMode?
    ) throws -> URLRequest {
        let configuration = try configuration.validated()
        let apiKey = try validatedAPIKey(apiKey)
        let body = OpenAIResponsesRequest(
            model: configuration.model,
            input: [
                .init(
                    role: "system",
                    content: [.init(type: "input_text", text: systemPrompt)]
                ),
                .init(
                    role: "user",
                    content: [.init(type: "input_text", text: userMessage)]
                ),
            ],
            text: mode == .structuredJSON
                ? .init(format: .jsonSchema)
                : nil,
            maxOutputTokens: maxOutputTokens,
            reasoning: thinking == .disabled ? .init(effort: "none") : nil
        )
        return try jsonRequest(
            url: AIEndpointResolver.resolve(configuration: configuration),
            body: body,
            timeout: timeout,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
    }

    func responseText(from data: Data, response: HTTPURLResponse) throws -> String {
        try validateAIHTTPStatus(response.statusCode)
        let envelope: OpenAIResponsesEnvelope
        do {
            envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        } catch {
            throw AIError.invalidResponse("Could not decode Responses API envelope")
        }
        if envelope.incompleteDetails?.reason == "max_output_tokens"
            || envelope.status == "incomplete" {
            throw AIError.truncatedResponse
        }
        let text = envelope.output
            .flatMap(\.content)
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !text.isEmpty else {
            throw AIError.invalidResponse("Responses API returned no output text")
        }
        return text
    }
}

private struct OpenAICompatibleChatAdapter: AIProviderAdapter {
    func makeRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        mode: AIProviderResponseMode,
        timeout: TimeInterval,
        maxOutputTokens: Int?,
        thinking: AIThinkingMode?
    ) throws -> URLRequest {
        let configuration = try configuration.validated()
        let apiKey = try validatedAPIKey(apiKey)
        let body = OpenAICompatibleRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userMessage),
            ],
            responseFormat: mode == .structuredJSON ? .jsonSchema : nil,
            temperature: 0,
            maxTokens: maxOutputTokens,
            thinking: thinking.map { .init(type: $0.rawValue) }
        )
        return try jsonRequest(
            url: AIEndpointResolver.resolve(configuration: configuration),
            body: body,
            timeout: timeout,
            headers: ["Authorization": "Bearer \(apiKey)"]
        )
    }

    func responseText(from data: Data, response: HTTPURLResponse) throws -> String {
        try validateAIHTTPStatus(response.statusCode)
        let envelope: OpenAICompatibleEnvelope
        do {
            envelope = try JSONDecoder().decode(OpenAICompatibleEnvelope.self, from: data)
        } catch {
            throw AIError.invalidResponse("Could not decode Chat Completions envelope")
        }
        guard let choice = envelope.choices.first else {
            throw AIError.invalidResponse("Chat Completions returned no choice")
        }
        if choice.finishReason == "length" {
            throw AIError.truncatedResponse
        }
        let text = choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIError.invalidResponse("Chat Completions returned empty content")
        }
        return text
    }
}

private struct AnthropicMessagesAdapter: AIProviderAdapter {
    func makeRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        mode: AIProviderResponseMode,
        timeout: TimeInterval,
        maxOutputTokens: Int?,
        thinking: AIThinkingMode?
    ) throws -> URLRequest {
        let configuration = try configuration.validated()
        let apiKey = try validatedAPIKey(apiKey)
        let body = AnthropicMessagesRequest(
            model: configuration.model,
            maxTokens: maxOutputTokens ?? (mode == .structuredJSON ? 8_192 : 256),
            system: systemPrompt,
            messages: [.init(role: "user", content: userMessage)]
        )
        return try jsonRequest(
            url: AIEndpointResolver.resolve(configuration: configuration),
            body: body,
            timeout: timeout,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ]
        )
    }

    func responseText(from data: Data, response: HTTPURLResponse) throws -> String {
        try validateAIHTTPStatus(response.statusCode)
        let envelope: AnthropicMessagesEnvelope
        do {
            envelope = try JSONDecoder().decode(AnthropicMessagesEnvelope.self, from: data)
        } catch {
            throw AIError.invalidResponse("Could not decode Messages API envelope")
        }
        if envelope.stopReason == "max_tokens" {
            throw AIError.truncatedResponse
        }
        guard let text = envelope.content
            .first(where: { $0.type == "text" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw AIError.invalidResponse("Messages API returned no text content")
        }
        return text
    }
}

private func validatedAPIKey(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AIError.missingAPIKey }
    return trimmed
}

private func jsonRequest<Body: Encodable>(
    url: URL,
    body: Body,
    timeout: TimeInterval,
    headers: [String: String]
) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // AI responses are request-body dependent. Do not let URLCache reuse a
    // previous completion just because the endpoint URL is the same.
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    for (name, value) in headers {
        request.setValue(value, forHTTPHeaderField: name)
    }
    do {
        request.httpBody = try JSONEncoder().encode(body)
    } catch {
        throw AIError.invalidResponse("Could not encode provider request")
    }
    return request
}

func validateAIHTTPStatus(_ status: Int) throws {
    switch status {
    case 200..<300:
        return
    case 401, 403:
        throw AIError.unauthorized
    case 429:
        throw AIError.rateLimited
    case 408, 425, 500...599:
        throw AIError.transientHTTPStatus(status)
    default:
        throw AIError.httpStatus(status)
    }
}

private struct OpenAIResponsesRequest: Encodable {
    let model: String
    let input: [Input]
    let text: TextOptions?
    let maxOutputTokens: Int?
    let reasoning: ReasoningOptions?

    enum CodingKeys: String, CodingKey {
        case model, input, text
        case maxOutputTokens = "max_output_tokens"
        case reasoning
    }

    struct Input: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let text: String
    }

    struct TextOptions: Encodable {
        let format: Format
    }

    struct Format: Encodable {
        let type: String
        let name: String?
        let strict: Bool?
        let schema: StructuredJSONSchema?

        static let jsonSchema = Format(
            type: "json_schema",
            name: "interview_flashcard_response",
            strict: false,
            schema: StructuredJSONSchema()
        )
    }

    /// OpenCode Go exposes the OpenAI Responses API and supports Structured
    /// Outputs.  The schema is intentionally envelope-level here: individual
    /// response models still perform the strict domain validation after
    /// decoding, while the provider guarantees that the transport payload is
    /// JSON instead of prose or Markdown.
    struct ReasoningOptions: Encodable {
        let effort: String
    }
}

private struct OpenAIResponsesEnvelope: Decodable {
    let output: [Output]
    let status: String?
    let incompleteDetails: IncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case output, status
        case incompleteDetails = "incomplete_details"
    }

    struct Output: Decodable {
        let content: [Content]
    }

    struct Content: Decodable {
        let type: String
        let text: String?
    }

    struct IncompleteDetails: Decodable {
        let reason: String?
    }
}

private struct OpenAICompatibleRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat?
    let temperature: Int
    let maxTokens: Int?
    let thinking: ThinkingOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
        case thinking
    }

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
        let jsonSchema: JSONSchema?

        static let jsonSchema = ResponseFormat(
            type: "json_schema",
            jsonSchema: JSONSchema(
                name: "interview_flashcard_response",
                strict: false,
                schema: StructuredJSONSchema()
            )
        )

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    struct JSONSchema: Encodable {
        let name: String
        let strict: Bool
        let schema: StructuredJSONSchema
    }

    struct ThinkingOptions: Encodable {
        let type: String
    }
}

private struct StructuredJSONSchema: Encodable {
    let type = "object"
    let additionalProperties = true
}

private struct OpenAICompatibleEnvelope: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct AnthropicMessagesEnvelope: Decodable {
    let content: [Content]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    struct Content: Decodable {
        let type: String
        let text: String
    }
}
