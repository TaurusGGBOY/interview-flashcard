import Foundation

enum AIConfigurationSettingsKey {
    static let provider = "settings.ai.configuration.provider"
    static let baseURL = "settings.ai.configuration.base-url"
    static let model = "settings.ai.configuration.model"
    static let migrationVersion = "settings.ai.configuration.migration-version"
    static let currentMigrationVersion = 6

    /// Kept only to recognize the legacy built-in value during migration.
    /// New configurations must never use api.deepseek.com (it is pay-per-use;
    /// the subscription endpoint is OpenCode Go).
    fileprivate static let legacyDeepSeekBaseURL = "https://api.deepseek.com"
    fileprivate static let legacyDeepSeekModel = "settings.deepseek.model"
}

enum AIConfigurationEnvironmentKey {
    /// DEBUG-only launch overrides used by local provider smoke tests. They
    /// keep machine-local relay settings out of the app bundle and release
    /// builds while allowing the acceptance launcher to use the active
    /// cc-switch endpoint.
    static let deepSeekBaseURL = "INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL"
    static let deepSeekModel = "INTERVIEW_FLASHCARD_DEEPSEEK_MODEL"
    /// The active provider protocol is explicit so a relay is never contacted
    /// with the wrong request/response protocol.
    static let deepSeekProvider = "INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER"
    static let deepSeekAPIKey = "INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY"
}

enum AIConfigurationEnvironment {
    static func configuration(from environment: [String: String]) -> AIProviderConfiguration? {
        guard let baseURL = environment[AIConfigurationEnvironmentKey.deepSeekBaseURL],
              let model = environment[AIConfigurationEnvironmentKey.deepSeekModel],
              !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        let provider = environment[AIConfigurationEnvironmentKey.deepSeekProvider]
            .flatMap { AIProviderKind(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            ?? .openAI
        return try? AIProviderConfiguration(
            provider: provider,
            baseURL: baseURL,
            model: model
        ).validated()
    }
}

protocol AIConfigurationStore: Sendable {
    func load() -> AIProviderConfiguration
    func save(_ configuration: AIProviderConfiguration)
}

final class UserDefaultsAIConfigurationStore: AIConfigurationStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let environment: [String: String]
    private let lock = NSLock()

    init(
        userDefaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.userDefaults = userDefaults
        self.environment = environment
    }

    func load() -> AIProviderConfiguration {
        lock.withLock {
            migrateIfNeeded()
#if DEBUG
            if let environmentConfiguration = debugEnvironmentConfiguration() {
                return environmentConfiguration
            }
#endif
            let provider = userDefaults.string(forKey: AIConfigurationSettingsKey.provider)
                .flatMap(AIProviderKind.init(rawValue:))
            let stored: AIProviderConfiguration
            if let provider {
                stored = AIProviderConfiguration(
                    provider: provider,
                    baseURL: userDefaults.string(forKey: AIConfigurationSettingsKey.baseURL)
                        ?? provider.defaultConfiguration.baseURL,
                    model: userDefaults.string(forKey: AIConfigurationSettingsKey.model)
                        ?? provider.defaultConfiguration.model
                )
            } else {
                // Fresh installs default to OpenCode Go Chat Completions.
                stored = .openCodeGo
            }
            guard let validated = try? stored.validated() else {
                let fallback = provider?.defaultConfiguration ?? .openCodeGo
                persist(fallback)
                return fallback
            }
            return validated
        }
    }

#if DEBUG
    private func debugEnvironmentConfiguration() -> AIProviderConfiguration? {
        AIConfigurationEnvironment.configuration(from: environment)
    }
#endif

    func save(_ configuration: AIProviderConfiguration) {
        lock.withLock {
            persist(configuration)
            userDefaults.set(
                AIConfigurationSettingsKey.currentMigrationVersion,
                forKey: AIConfigurationSettingsKey.migrationVersion
            )
        }
    }

    private func migrateIfNeeded() {
        let storedVersion = userDefaults.integer(forKey: AIConfigurationSettingsKey.migrationVersion)

        if storedVersion < 1 {
            if userDefaults.string(forKey: AIConfigurationSettingsKey.provider) == nil {
                let legacyModel = userDefaults
                    .string(forKey: AIConfigurationSettingsKey.legacyDeepSeekModel)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var migrated = AIProviderConfiguration.openCodeGo
                if let legacyModel, !legacyModel.isEmpty {
                    migrated.model = legacyModel
                }
                persist(migrated)
            }
            userDefaults.set(1, forKey: AIConfigurationSettingsKey.migrationVersion)
        }

        let provider = userDefaults.string(forKey: AIConfigurationSettingsKey.provider)
            .flatMap(AIProviderKind.init(rawValue:))
        let baseURL = userDefaults.string(forKey: AIConfigurationSettingsKey.baseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let model = userDefaults.string(forKey: AIConfigurationSettingsKey.model)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if storedVersion < 2 {
            // Version 1's built-in default was direct DeepSeek. It was never
            // the intended physical-device endpoint: OpenCode Go exposes this
            // model through the OpenAI Responses API. Migrate only that exact
            // built-in value; a custom provider/base URL remains the user's
            // explicit choice.
            if provider == .openAICompatible,
               baseURL == AIConfigurationSettingsKey.legacyDeepSeekBaseURL,
               model == "deepseek-v4-flash" {
                persist(.openCodeGo)
            }
            userDefaults.set(2, forKey: AIConfigurationSettingsKey.migrationVersion)
        }

        if storedVersion < 3 {
            // Version 2 routed OpenCode Go through Anthropic Messages, which
            // the relay does not speak (it returns Responses API envelopes).
            // Rewrite that exact persisted value to the Responses-based
            // configuration; a custom provider/base URL stays untouched.
            if provider == .anthropic,
               baseURL == "https://opencode.ai/zen/go",
               model == "deepseek-v4-flash" {
                persist(.openCodeGo)
            }
            userDefaults.set(3, forKey: AIConfigurationSettingsKey.migrationVersion)
        }

        if storedVersion < 4 {
            // Version 3's built-in OpenCode Go model was DeepSeek V4 Flash.
            // Migrate only that exact endpoint/model pair so an explicitly
            // configured custom model is not overwritten.
            if provider == .openAI,
               baseURL == "https://opencode.ai/zen/go",
               model == "deepseek-v4-flash" {
                persist(.openCodeGo)
            }
            userDefaults.set(4, forKey: AIConfigurationSettingsKey.migrationVersion)
        }

        if storedVersion < 5 {
            // Migrate the previous OpenAI Responses selection to the
            // OpenCode Go Chat Completions endpoint.
            if provider == .openAI,
               baseURL == "https://opencode.ai/zen/go",
               model == "deepseek-v4-flash" {
                persist(.openCodeGo)
            }
            userDefaults.set(5, forKey: AIConfigurationSettingsKey.migrationVersion)
        }

        if storedVersion < 6 {
            // Version 5 temporarily selected MiMo V2.5 as the built-in
            // OpenCode Go model. Move only that exact built-in value to the
            // current DeepSeek V4 Flash default; explicit custom models stay
            // untouched.
            if provider == .openAICompatible,
               baseURL == "https://opencode.ai/zen/go",
               model == "mimo-v2.5" {
                persist(.openCodeGo)
            }
            userDefaults.set(6, forKey: AIConfigurationSettingsKey.migrationVersion)
        }
    }

    private func persist(_ configuration: AIProviderConfiguration) {
        userDefaults.set(configuration.provider.rawValue, forKey: AIConfigurationSettingsKey.provider)
        userDefaults.set(configuration.baseURL, forKey: AIConfigurationSettingsKey.baseURL)
        userDefaults.set(configuration.model, forKey: AIConfigurationSettingsKey.model)
    }
}

final class InMemoryAIConfigurationStore: AIConfigurationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: AIProviderConfiguration

    init(configuration: AIProviderConfiguration = .openCodeGo) {
        self.configuration = configuration
    }

    func load() -> AIProviderConfiguration {
        lock.withLock { configuration }
    }

    func save(_ configuration: AIProviderConfiguration) {
        lock.withLock {
            self.configuration = configuration
        }
    }
}
