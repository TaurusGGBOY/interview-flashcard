import Foundation
import XCTest

final class AISettingsDraftTests: XCTestCase {
    func testDraftCopiesSavedConfigurationAndKeyWithoutMutatingSource() {
        let saved = AIProviderConfiguration(
            provider: .openAICompatible,
            baseURL: "https://saved.example.com/v1",
            model: "saved-model"
        )

        var draft = AISettingsDraft(configuration: saved, apiKey: "saved-key")
        draft.baseURL = "https://draft.example.com"
        draft.model = "draft-model"
        draft.apiKey = "draft-key"

        XCTAssertEqual(saved.baseURL, "https://saved.example.com/v1")
        XCTAssertEqual(saved.model, "saved-model")
        XCTAssertEqual(draft.apiKey, "draft-key")
    }

    func testSelectingProviderAppliesDefaultsAndClearsKey() {
        var draft = AISettingsDraft(
            configuration: .init(
                provider: .openAICompatible,
                baseURL: "https://custom.example.com",
                model: "custom-model"
            ),
            apiKey: "old-provider-key"
        )

        draft.selectProvider(.anthropic)

        XCTAssertEqual(draft.provider, .anthropic)
        XCTAssertEqual(draft.baseURL, "https://api.anthropic.com")
        XCTAssertEqual(draft.model, "claude-sonnet-5")
        XCTAssertEqual(draft.apiKey, "")
    }

    func testEmptyKeyCanBeSavedToDeleteButCannotBeTested() {
        let draft = AISettingsDraft(
            configuration: AIProviderKind.openAI.defaultConfiguration,
            apiKey: ""
        )

        XCTAssertTrue(draft.canSave)
        XCTAssertFalse(draft.canTest)
        XCTAssertNoThrow(try draft.validatedConfiguration())
    }

    func testInvalidURLOrModelDisablesSaveAndTest() {
        var draft = AISettingsDraft(
            configuration: AIProviderKind.openAI.defaultConfiguration,
            apiKey: "key"
        )
        draft.baseURL = "not-a-url"
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.canTest)

        draft.baseURL = "https://api.openai.com"
        draft.model = " \n"
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.canTest)
    }

    func testConnectionErrorMessagesAreSpecificAndDoNotLeakSecrets() {
        let cases: [(AIError, String)] = [
            (.missingAPIKey, "请输入 API Key"),
            (.unauthorized, "认证失败，请检查 API Key"),
            (.rateLimited, "请求过于频繁，请稍后重试"),
            (.httpStatus(404), "模型或接口地址不可用"),
            (.transport(String(describing: URLError.Code.timedOut)), "连接超时，请检查网络或服务地址"),
            (.invalidResponse("secret-marker"), "服务已响应，但返回格式无法识别"),
        ]

        for (error, expected) in cases {
            let message = AISettingsDraft.connectionErrorMessage(for: error)
            XCTAssertEqual(message, expected)
            XCTAssertFalse(message.contains("secret-marker"))
        }
    }

    func testSuccessSummaryIsTrimmedAndBounded() {
        let longReply = "  " + String(repeating: "好", count: 120) + "  "

        let message = AISettingsDraft.connectionSuccessMessage(reply: longReply)

        XCTAssertTrue(message.hasPrefix("连接成功："))
        XCTAssertLessThanOrEqual(message.count, 86)
        XCTAssertFalse(message.hasSuffix(" "))
    }
}
