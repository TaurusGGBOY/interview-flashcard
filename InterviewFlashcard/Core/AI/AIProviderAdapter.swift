import Foundation

enum AIProviderResponseMode: Equatable, Sendable {
    case structuredJSON
    case plainText
}

enum AIResponseSchema: CaseIterable, Equatable, Sendable {
    case generic
    case decompose
    case referenceAnswer
    case refine
    case reclassify
    case polish
    case evaluateScore
    case evaluate
    case evaluationFeedback
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
        responseSchema: AIResponseSchema,
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
        responseSchema: AIResponseSchema,
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
                ? .init(format: .jsonSchema(for: responseSchema))
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
        let responseOutput = envelope.output?
            .flatMap(\.content)
            .filter { $0.type == "output_text" || $0.type == "text" }
            .compactMap { $0.text ?? $0.value }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n") ?? ""
        let chatOutput = envelope.choices?
            .compactMap { $0.message.content }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n") ?? ""
        let text = [envelope.outputText ?? "", responseOutput, chatOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard !text.isEmpty else {
            throw AIError.invalidResponse(
                "Responses API returned no output text（结构：\(Self.responseShape(data))）"
            )
        }
        return text
    }

    private static func responseShape(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return "非 JSON"
        }
        guard let dictionary = object as? [String: Any] else {
            return String(describing: type(of: object))
        }
        let keys = dictionary.keys.sorted().joined(separator: ",")
        let arrayCounts = dictionary.keys.sorted().compactMap { key -> String? in
            guard let values = dictionary[key] as? [Any] else { return nil }
            return "\(key).count=\(values.count)"
        }
        return "keys=\(keys); \(arrayCounts.joined(separator: ","))"
    }
}

private struct OpenAICompatibleChatAdapter: AIProviderAdapter {
    func makeRequest(
        configuration: AIProviderConfiguration,
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        mode: AIProviderResponseMode,
        responseSchema: AIResponseSchema,
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
            responseFormat: mode == .structuredJSON
                ? .jsonSchema(for: responseSchema)
                : nil,
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
        responseSchema: AIResponseSchema,
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

        static func jsonSchema(for responseSchema: AIResponseSchema) -> Format {
            Format(
                type: "json_schema",
                name: "interview_flashcard_response",
                strict: false,
                schema: StructuredJSONSchema(responseSchema)
            )
        }
    }

    /// OpenAI Responses supports Structured Outputs. Individual response
    /// models still perform domain validation after decoding, while this
    /// request guarantees that the transport payload is JSON.
    struct ReasoningOptions: Encodable {
        let effort: String
    }
}

private struct OpenAIResponsesEnvelope: Decodable {
    let output: [Output]?
    let outputText: String?
    let choices: [Choice]?
    let status: String?
    let incompleteDetails: IncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case output, choices, status
        case outputText = "output_text"
        case incompleteDetails = "incomplete_details"
    }

    struct Output: Decodable {
        let content: [Content]
    }

    struct Content: Decodable {
        let type: String
        let text: String?
        let value: String?
    }

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
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

        static func jsonSchema(for responseSchema: AIResponseSchema) -> ResponseFormat {
            ResponseFormat(
                type: "json_schema",
                jsonSchema: JSONSchema(
                    name: "interview_flashcard_response",
                    strict: false,
                    schema: StructuredJSONSchema(responseSchema)
                )
            )
        }

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
    private let node: JSONSchemaNode

    init(_ responseSchema: AIResponseSchema = .generic) {
        switch responseSchema {
        case .generic:
            node = .object(properties: [:], required: [], additionalProperties: true)
        default:
            node = .schema(for: responseSchema)
        }
    }

    func encode(to encoder: Encoder) throws {
        try node.encode(to: encoder)
    }
}

private indirect enum JSONSchemaNode: Encodable, Sendable {
    case object(
        properties: [String: JSONSchemaNode],
        required: [String],
        additionalProperties: Bool
    )
    case array(items: JSONSchemaNode)
    case string
    case integer
    case number
    case any

    static func schema(for responseSchema: AIResponseSchema) -> JSONSchemaNode {
        switch responseSchema {
        case .decompose:
            return requiredObject(["candidates", "completionStatus"], arrays: ["candidates"])
        case .referenceAnswer:
            return requiredObject(["answerText", "keyPoints", "modelID", "promptVersion", "completionStatus"], arrays: ["keyPoints"])
        case .refine:
            return requiredObject(["cards", "completionStatus"], arrays: ["cards"])
        case .reclassify:
            return requiredObject(["assignments", "completionStatus"], arrays: ["assignments"])
        case .polish:
            return requiredObject(
                ["polishedText", "edits", "suspectedTranscriptionIssues", "introducedClaims", "needsUserReview", "warnings", "modelID", "promptVersion", "completionStatus"],
                arrays: ["edits", "suspectedTranscriptionIssues", "introducedClaims", "warnings"]
            )
        case .evaluateScore:
            return requiredObject(
                ["scorable", "notScorableReason", "dimensions", "confidence", "scoreRange", "warnings", "modelID", "promptVersion", "rubricVersion", "completionStatus"],
                arrays: ["dimensions", "warnings"],
                objects: ["scoreRange"]
            )
        case .evaluate:
            return evaluationObject(includeScorable: true)
        case .evaluationFeedback:
            return evaluationObject(includeScorable: false)
        case .generic:
            return .object(properties: [:], required: [], additionalProperties: true)
        }
    }

    private static func requiredObject(
        _ keys: [String],
        arrays: Set<String> = [],
        objects: Set<String> = []
    ) -> JSONSchemaNode {
        let properties = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, arrays.contains(key) ? JSONSchemaNode.array(items: .any) : objects.contains(key) ? .object(properties: [:], required: [], additionalProperties: true) : .any)
        })
        return .object(properties: properties, required: keys, additionalProperties: true)
    }

    private static func evaluationObject(includeScorable: Bool) -> JSONSchemaNode {
        var properties: [String: JSONSchemaNode] = [
            "dimensions": .array(items: .any),
            "factualErrors": .array(items: .any),
            "strengths": .array(items: .string),
            "gapsAndErrors": .array(items: .string),
            "improvements": .array(items: .string),
            "polishOnlyClaims": .array(items: .string),
            "confidence": .number,
            "scoreRange": .object(
                properties: ["low": .integer, "high": .integer],
                required: ["low", "high"],
                additionalProperties: true
            ),
            "warnings": .array(items: .string),
            "modelID": .string,
            "promptVersion": .string,
            "rubricVersion": .string,
            "completionStatus": .string,
        ]
        var required = [
            "dimensions", "factualErrors", "strengths", "gapsAndErrors",
            "improvements", "polishOnlyClaims", "confidence", "scoreRange",
            "warnings", "modelID", "promptVersion", "rubricVersion",
            "completionStatus",
        ]
        if includeScorable {
            properties["scorable"] = .any
            properties["notScorableReason"] = .any
            required.insert("scorable", at: 0)
            required.insert("notScorableReason", at: 1)
        }
        return .object(properties: properties, required: required, additionalProperties: true)
    }

    static let evaluationFeedback: JSONSchemaNode = .object(
        properties: [
            "dimensions": .array(items: .object(
                properties: [
                    "key": .string,
                    "evidence": .array(items: .object(
                        properties: ["quote": .string, "explanation": .string],
                        required: ["quote", "explanation"],
                        additionalProperties: true
                    )),
                    "missedPoints": .array(items: .string),
                    "feedback": .string,
                ],
                required: ["key", "evidence", "missedPoints", "feedback"],
                additionalProperties: true
            )),
            "factualErrors": .array(items: .object(
                properties: [
                    "statement": .string,
                    "explanation": .string,
                    "referenceBasis": .string,
                ],
                required: ["statement", "explanation", "referenceBasis"],
                additionalProperties: true
            )),
            "strengths": .array(items: .string),
            "gapsAndErrors": .array(items: .string),
            "improvements": .array(items: .string),
            "polishOnlyClaims": .array(items: .string),
            "confidence": .number,
            "scoreRange": .object(
                properties: ["low": .integer, "high": .integer],
                required: ["low", "high"],
                additionalProperties: true
            ),
            "warnings": .array(items: .string),
            "modelID": .string,
            "promptVersion": .string,
            "rubricVersion": .string,
            "completionStatus": .string,
        ],
        required: [
            "dimensions", "factualErrors", "strengths", "gapsAndErrors",
            "improvements", "polishOnlyClaims", "confidence", "scoreRange",
            "warnings", "modelID", "promptVersion", "rubricVersion",
            "completionStatus",
        ],
        additionalProperties: true
    )

    func encode(to encoder: Encoder) throws {
        if case .any = self {
            var anyContainer = encoder.singleValueContainer()
            try anyContainer.encode([String: String]())
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .object(properties, required, additionalProperties):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
            try container.encode(additionalProperties, forKey: .additionalProperties)
        case let .array(items):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
        case .string:
            try container.encode("string", forKey: .type)
        case .integer:
            try container.encode("integer", forKey: .type)
        case .number:
            try container.encode("number", forKey: .type)
        case .any:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, properties, required, additionalProperties, items
    }
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
