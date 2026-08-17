import Foundation
import XCTest

final class AIProviderConfigurationTests: XCTestCase {
    func testProviderDefaultsMatchProductContract() {
        XCTAssertEqual(
            AIProviderKind.openAI.defaultConfiguration,
            AIProviderConfiguration(
                provider: .openAI,
                baseURL: "https://api.openai.com",
                model: "gpt-5.6-terra"
            )
        )
        XCTAssertEqual(
            AIProviderKind.openAICompatible.defaultConfiguration,
            AIProviderConfiguration(
                provider: .openAICompatible,
                baseURL: "https://opencode.ai/zen/go",
                model: "deepseek-v4-flash"
            )
        )
        XCTAssertEqual(
            AIProviderKind.anthropic.defaultConfiguration,
            AIProviderConfiguration(
                provider: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude-sonnet-5"
            )
        )
        XCTAssertEqual(
            AIProviderKind.allCases.map(\.displayName),
            ["OpenAI", "OpenAI 兼容", "Anthropic"]
        )
        XCTAssertEqual(
            AIProviderConfiguration.openCodeGo,
            AIProviderConfiguration(
                provider: .openAI,
                baseURL: "https://opencode.ai/zen/go",
                model: "gpt-5.6-luna"
            )
        )
    }

    func testEndpointResolutionHandlesRootV1PrefixAndFullEndpoint() throws {
        XCTAssertEqual(
            try endpoint(.openAI, "https://api.openai.com/"),
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(
            try endpoint(.openAI, "https://proxy.example.com/gateway/v1"),
            "https://proxy.example.com/gateway/v1/responses"
        )
        XCTAssertEqual(
            try endpoint(.openAI, "https://proxy.example.com/gateway/v1/responses"),
            "https://proxy.example.com/gateway/v1/responses"
        )
        XCTAssertEqual(
            try endpoint(.openAICompatible, "https://proxy.example.com/v1"),
            "https://proxy.example.com/v1/chat/completions"
        )
        XCTAssertEqual(
            try endpoint(.anthropic, "https://api.anthropic.com"),
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            try endpoint(.openAI, "https://opencode.ai/zen/go"),
            "https://opencode.ai/zen/go/v1/responses"
        )
    }

    func testConfigurationValidationRejectsUnsafeOrIncompleteValues() {
        let invalidBaseURLs = [
            "",
            "api.example.com",
            "ftp://api.example.com",
            "https:///v1",
            "https://api.example.com?token=secret",
            "https://api.example.com/#fragment",
        ]

        for baseURL in invalidBaseURLs {
            XCTAssertThrowsError(
                try AIProviderConfiguration(
                    provider: .openAI,
                    baseURL: baseURL,
                    model: "gpt-test"
                ).validated(),
                "Expected invalid Base URL: \(baseURL)"
            )
        }

        XCTAssertThrowsError(
            try AIProviderConfiguration(
                provider: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: " \n"
            ).validated()
        )
    }

    func testConfigurationCodableRoundTrip() throws {
        let configuration = AIProviderConfiguration(
            provider: .anthropic,
            baseURL: "https://proxy.example.com/claude/v1",
            model: "custom-claude"
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AIProviderConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
    }

    private func endpoint(_ provider: AIProviderKind, _ baseURL: String) throws -> String {
        try AIEndpointResolver.resolve(
            configuration: AIProviderConfiguration(
                provider: provider,
                baseURL: baseURL,
                model: "test-model"
            )
        ).absoluteString
    }
}
