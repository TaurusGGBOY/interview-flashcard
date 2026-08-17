import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case openAICompatible = "openai-compatible"
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }

    var defaultConfiguration: AIProviderConfiguration {
        switch self {
        case .openAI:
            AIProviderConfiguration(
                provider: self,
                baseURL: "https://api.openai.com",
                model: "gpt-5.6-terra"
            )
        case .openAICompatible:
            AIProviderConfiguration(
                provider: self,
                // The subscription endpoint is OpenCode Go. Note that OpenCode
                // Go speaks the Responses API (/v1/responses), not Chat
                // Completions; prefer .openCodeGo below for that service.
                baseURL: "https://opencode.ai/zen/go",
                model: "deepseek-v4-flash"
            )
        case .anthropic:
            AIProviderConfiguration(
                provider: self,
                baseURL: "https://api.anthropic.com",
                model: "claude-sonnet-5"
            )
        }
    }

    fileprivate var endpointPathComponents: [String] {
        switch self {
        case .openAI: ["v1", "responses"]
        case .openAICompatible: ["chat", "completions"]
        case .anthropic: ["v1", "messages"]
        }
    }
}

struct AIProviderConfiguration: Codable, Equatable, Sendable {
    var provider: AIProviderKind
    var baseURL: String
    var model: String

    func validated() throws -> AIProviderConfiguration {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw AIConfigurationError.missingModel
        }
        try AIEndpointResolver.validate(baseURL: trimmedBaseURL)
        return AIProviderConfiguration(
            provider: provider,
            baseURL: trimmedBaseURL,
            model: trimmedModel
        )
    }
}

extension AIProviderConfiguration {
    /// OpenCode Go's public subscription endpoint speaks the OpenAI Responses
    /// API. This is the default provider for new installs and the migration
    /// target for legacy DeepSeek settings.
    static let openCodeGo = AIProviderConfiguration(
        provider: .openAI,
        baseURL: "https://opencode.ai/zen/go",
        model: "gpt-5.6-luna"
    )
}

enum AIConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case invalidBaseURL
    case unsupportedURLScheme
    case baseURLContainsQueryOrFragment
    case missingModel

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "请输入完整的 Base URL"
        case .unsupportedURLScheme:
            "Base URL 必须使用 HTTP 或 HTTPS"
        case .baseURLContainsQueryOrFragment:
            "Base URL 不能包含查询参数或锚点"
        case .missingModel:
            "请输入模型名称"
        }
    }
}

enum AIEndpointResolver {
    static func resolve(configuration: AIProviderConfiguration) throws -> URL {
        let configuration = try configuration.validated()
        guard var components = URLComponents(string: configuration.baseURL) else {
            throw AIConfigurationError.invalidBaseURL
        }

        let baseComponents = components.path
            .split(separator: "/")
            .map(String.init)
        let endpointComponents = configuration.provider.endpointPathComponents
        let overlap = largestOverlap(
            suffixOf: baseComponents,
            prefixOf: endpointComponents
        )
        let resolvedComponents = baseComponents + endpointComponents.dropFirst(overlap)
        components.path = "/" + resolvedComponents.joined(separator: "/")

        guard let url = components.url else {
            throw AIConfigurationError.invalidBaseURL
        }
        return url
    }

    fileprivate static func validate(baseURL: String) throws {
        guard !baseURL.isEmpty,
              let components = URLComponents(string: baseURL),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            throw AIConfigurationError.invalidBaseURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw AIConfigurationError.unsupportedURLScheme
        }
        guard components.query == nil, components.fragment == nil else {
            throw AIConfigurationError.baseURLContainsQueryOrFragment
        }
    }

    private static func largestOverlap(
        suffixOf base: [String],
        prefixOf endpoint: [String]
    ) -> Int {
        let maximum = min(base.count, endpoint.count)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1) {
            if Array(base.suffix(length)) == Array(endpoint.prefix(length)) {
                return length
            }
        }
        return 0
    }
}
