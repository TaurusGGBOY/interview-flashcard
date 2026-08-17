import Foundation
import XCTest

final class AIConfigurationStoreTests: XCTestCase {
    func testNewConfigurationRoundTripsWithoutUsingLegacyLaunchProviderKey() {
        withDefaults(named: #function) { defaults in
            defaults.set("deepseek", forKey: "settings.ai.provider")
            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)
            let expected = AIProviderConfiguration(
                provider: .anthropic,
                baseURL: "https://proxy.example.com/anthropic",
                model: "claude-custom"
            )

            store.save(expected)

            XCTAssertEqual(store.load(), expected)
            XCTAssertEqual(defaults.string(forKey: "settings.ai.provider"), "deepseek")
        }
    }

    func testLegacyDeepSeekModelMigratesOnceToOpenCodeGoDefault() {
        withDefaults(named: #function) { defaults in
            defaults.set("legacy-deepseek-model", forKey: "settings.deepseek.model")
            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(
                store.load(),
                AIProviderConfiguration(
                    provider: .openAI,
                    baseURL: "https://opencode.ai/zen/go",
                    model: "legacy-deepseek-model"
                )
            )

            defaults.set("must-not-overwrite", forKey: "settings.deepseek.model")
            XCTAssertEqual(store.load().model, "legacy-deepseek-model")
        }
    }

    func testMissingLegacyModelUsesOpenCodeGoDefault() {
        withDefaults(named: #function) { defaults in
            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(store.load(), .openCodeGo)
        }
    }

    func testVersionThreeOpenCodeGoDeepSeekDefaultMigratesToLuna() {
        withDefaults(named: #function) { defaults in
            defaults.set("openai", forKey: AIConfigurationSettingsKey.provider)
            defaults.set("https://opencode.ai/zen/go", forKey: AIConfigurationSettingsKey.baseURL)
            defaults.set("deepseek-v4-flash", forKey: AIConfigurationSettingsKey.model)
            defaults.set(3, forKey: AIConfigurationSettingsKey.migrationVersion)

            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(store.load(), .openCodeGo)
            XCTAssertEqual(store.load().model, "gpt-5.6-luna")
            XCTAssertEqual(
                defaults.integer(forKey: AIConfigurationSettingsKey.migrationVersion),
                AIConfigurationSettingsKey.currentMigrationVersion
            )
        }
    }

    func testVersionTwoAnthropicOpenCodeGoMigratesToOpenAIResponses() {
        withDefaults(named: #function) { defaults in
            defaults.set("anthropic", forKey: AIConfigurationSettingsKey.provider)
            defaults.set("https://opencode.ai/zen/go", forKey: AIConfigurationSettingsKey.baseURL)
            defaults.set("deepseek-v4-flash", forKey: AIConfigurationSettingsKey.model)
            defaults.set(2, forKey: AIConfigurationSettingsKey.migrationVersion)

            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(store.load(), .openCodeGo)
            XCTAssertEqual(
                defaults.string(forKey: AIConfigurationSettingsKey.provider),
                AIProviderConfiguration.openCodeGo.provider.rawValue
            )
            XCTAssertEqual(
                defaults.string(forKey: AIConfigurationSettingsKey.baseURL),
                "https://opencode.ai/zen/go"
            )
            XCTAssertEqual(
                defaults.integer(forKey: AIConfigurationSettingsKey.migrationVersion),
                AIConfigurationSettingsKey.currentMigrationVersion
            )
        }
    }

    func testCustomAnthropicConfigurationIsNotRewrittenByMigration() {
        withDefaults(named: #function) { defaults in
            defaults.set("anthropic", forKey: AIConfigurationSettingsKey.provider)
            defaults.set("https://opencode.ai/zen/go", forKey: AIConfigurationSettingsKey.baseURL)
            defaults.set("custom-model", forKey: AIConfigurationSettingsKey.model)
            defaults.set(2, forKey: AIConfigurationSettingsKey.migrationVersion)

            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(
                store.load(),
                AIProviderConfiguration(
                    provider: .anthropic,
                    baseURL: "https://opencode.ai/zen/go",
                    model: "custom-model"
                )
            )
        }
    }

    func testVersionOneBuiltInDeepSeekDefaultMigratesToOpenCodeGo() {
        withDefaults(named: #function) { defaults in
            defaults.set("openai-compatible", forKey: AIConfigurationSettingsKey.provider)
            defaults.set("https://api.deepseek.com", forKey: AIConfigurationSettingsKey.baseURL)
            defaults.set("deepseek-v4-flash", forKey: AIConfigurationSettingsKey.model)
            defaults.set(1, forKey: AIConfigurationSettingsKey.migrationVersion)

            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(store.load(), .openCodeGo)
            XCTAssertEqual(
                defaults.string(forKey: AIConfigurationSettingsKey.provider),
                AIProviderConfiguration.openCodeGo.provider.rawValue
            )
            XCTAssertEqual(
                defaults.string(forKey: AIConfigurationSettingsKey.baseURL),
                AIProviderConfiguration.openCodeGo.baseURL
            )
            XCTAssertEqual(
                defaults.integer(forKey: AIConfigurationSettingsKey.migrationVersion),
                AIConfigurationSettingsKey.currentMigrationVersion
            )
        }
    }

    func testInvalidPersistedConfigurationFallsBackToEditableDefault() {
        withDefaults(named: #function) { defaults in
            defaults.set("anthropic", forKey: AIConfigurationSettingsKey.provider)
            defaults.set("not-a-url", forKey: AIConfigurationSettingsKey.baseURL)
            defaults.set("", forKey: AIConfigurationSettingsKey.model)
            defaults.set(
                AIConfigurationSettingsKey.currentMigrationVersion,
                forKey: AIConfigurationSettingsKey.migrationVersion
            )

            let store = UserDefaultsAIConfigurationStore(userDefaults: defaults)

            XCTAssertEqual(store.load(), AIProviderKind.anthropic.defaultConfiguration)
        }
    }

    func testDebugEnvironmentCanOverrideProviderEndpointWithoutPersistingIt() {
        withDefaults(named: #function) { defaults in
            defaults.set("openai-compatible", forKey: AIConfigurationSettingsKey.provider)
            defaults.set("https://legacy.example.com", forKey: AIConfigurationSettingsKey.baseURL)
            defaults.set("old-model", forKey: AIConfigurationSettingsKey.model)
            defaults.set(
                AIConfigurationSettingsKey.currentMigrationVersion,
                forKey: AIConfigurationSettingsKey.migrationVersion
            )
            let store = UserDefaultsAIConfigurationStore(
                userDefaults: defaults,
                environment: [
                    AIConfigurationEnvironmentKey.deepSeekBaseURL: "https://relay.example.com/v1",
                    AIConfigurationEnvironmentKey.deepSeekModel: "deepseek-v4-flash",
                    AIConfigurationEnvironmentKey.deepSeekProvider: "openai"
                ]
            )

#if DEBUG
            XCTAssertEqual(
                store.load(),
                AIProviderConfiguration(
                    provider: .openAI,
                    baseURL: "https://relay.example.com/v1",
                    model: "deepseek-v4-flash"
                )
            )
#else
            XCTAssertEqual(store.load().baseURL, "https://legacy.example.com")
            XCTAssertEqual(store.load().model, "old-model")
#endif
            XCTAssertEqual(defaults.string(forKey: AIConfigurationSettingsKey.baseURL), "https://legacy.example.com")
            XCTAssertEqual(defaults.string(forKey: AIConfigurationSettingsKey.model), "old-model")
        }
    }

    func testInMemoryStoreSupportsImmediateReplacement() {
        let store = InMemoryAIConfigurationStore(configuration: .openCodeGo)

        store.save(.init(
            provider: .openAI,
            baseURL: "https://api.openai.com",
            model: "second"
        ))

        XCTAssertEqual(store.load().provider, .openAI)
        XCTAssertEqual(store.load().model, "second")
    }

    private func withDefaults(
        named testName: String,
        body: (UserDefaults) -> Void
    ) {
        let suiteName = "AIConfigurationStoreTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
