import Foundation
import Observation

@MainActor
@Observable
public final class AppEnvironment {
    enum SettingsKey {
        static let deepSeekModel = "settings.deepseek.model"
        static let aiProvider = "settings.ai.provider"
    }

    public struct LaunchOptions: Equatable, Sendable {
        enum AIProvider: String, Sendable {
            case stub
            case deepseek
        }

        var diagnosticsEnabled: Bool
        var aiProvider: AIProvider
        var stubMode: String
        var seedFixture: String?
        var randomSeed: UInt64?
        var acceptanceImportFile: String?
        var acceptanceJSONFixtureFile: String?
        var jsonInboxImportRequested: Bool
        var acceptanceContinueRunID: UUID?
        var acceptanceConfirmRunID: UUID?
        public var keepAwakeWhileConnected: Bool

        static func current(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            userDefaults: UserDefaults = .standard
        ) -> LaunchOptions {
            let valueAfter: (String) -> String? = { flag in
                guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                    return nil
                }
                return arguments[index + 1]
            }

#if DEBUG
            let persistedProvider = AIProvider(rawValue: userDefaults.string(forKey: SettingsKey.aiProvider) ?? "")
            let provider = AIProvider(rawValue: valueAfter("-IFAIProvider") ?? "")
                ?? AIProvider(rawValue: environment["IF_DEFAULT_AI_PROVIDER"] ?? "")
                // A prior deterministic acceptance run may have persisted
                // "stub". Never let an icon launch silently reuse that mode.
                ?? (persistedProvider == .deepseek ? persistedProvider : nil)
                ?? .deepseek
            return LaunchOptions(
                diagnosticsEnabled: valueAfter("-IFDiagnosticsEnabled") == "YES",
                aiProvider: provider,
                stubMode: valueAfter("-IFStubMode") ?? "success",
                seedFixture: valueAfter("-IFSeedFixture"),
                randomSeed: valueAfter("-IFRandomSeed").flatMap(UInt64.init),
                acceptanceImportFile: valueAfter("-IFAcceptanceImportFile"),
                acceptanceJSONFixtureFile: valueAfter("-IFAcceptanceJSONFixtureFile"),
                jsonInboxImportRequested: valueAfter("-IFJSONInboxImport") == "YES",
                acceptanceContinueRunID: valueAfter("-IFAcceptanceContinueRunID").flatMap(UUID.init(uuidString:)),
                acceptanceConfirmRunID: valueAfter("-IFAcceptanceConfirmRunID").flatMap(UUID.init(uuidString:)),
                keepAwakeWhileConnected: valueAfter("-IFKeepAwake") == "YES"
            )
            #else
            return LaunchOptions(
                diagnosticsEnabled: false,
                aiProvider: .deepseek,
                stubMode: "success",
                seedFixture: nil,
                randomSeed: nil,
                acceptanceImportFile: nil,
                acceptanceJSONFixtureFile: nil,
                jsonInboxImportRequested: false,
                acceptanceContinueRunID: nil,
                acceptanceConfirmRunID: nil,
                keepAwakeWhileConnected: false
            )
            #endif
        }
    }

    struct Dependencies: Sendable {
        var now: @Sendable () -> Date
        var aiClient: any AIClient
        var apiKeyStore: any APIKeyStore
        var aiConfigurationStore: any AIConfigurationStore
        var aiConnectionTester: any AIConnectionTesting
        var practiceSettingsStore: any PracticeSettingsStore

        init(
            now: @escaping @Sendable () -> Date,
            aiClient: any AIClient,
            apiKeyStore: any APIKeyStore,
            aiConfigurationStore: any AIConfigurationStore,
            aiConnectionTester: any AIConnectionTesting,
            practiceSettingsStore: any PracticeSettingsStore = InMemoryPracticeSettingsStore()
        ) {
            self.now = now
            self.aiClient = aiClient
            self.apiKeyStore = apiKeyStore
            self.aiConfigurationStore = aiConfigurationStore
            self.aiConnectionTester = aiConnectionTester
            self.practiceSettingsStore = practiceSettingsStore
        }

        static let live: Dependencies = {
            let apiKeyStore = KeychainAPIKeyStore()
            let configurationStore = UserDefaultsAIConfigurationStore()
            let transport = URLSessionAIHTTPTransport()
            return Dependencies(
                now: { Date() },
                aiClient: RetryingAIClient(
                    base: DynamicAIClientRouter(
                        configurationStore: configurationStore,
                        apiKeyStore: apiKeyStore,
                        transport: transport
                    )
                ),
                apiKeyStore: apiKeyStore,
                aiConfigurationStore: configurationStore,
                aiConnectionTester: AIConnectionTester(transport: transport),
                practiceSettingsStore: UserDefaultsPracticeSettingsStore()
            )
        }()
    }

    public let launchOptions: LaunchOptions
    let dependencies: Dependencies
    @ObservationIgnored var importCoordinator: ImportCoordinator?
    private(set) var apiKeyConfigured = false
    private(set) var aiConfiguration: AIProviderConfiguration
    private(set) var practiceSettings: PracticeSettingsSnapshot

    init(
        launchOptions: LaunchOptions = .current(),
        dependencies: Dependencies = .live
    ) {
        self.launchOptions = launchOptions
        self.dependencies = dependencies
        aiConfiguration = dependencies.aiConfigurationStore.load()
        practiceSettings = dependencies.practiceSettingsStore.load()
    }

    public convenience init() {
        self.init(launchOptions: .current(), dependencies: .live)
    }

    var configuredModel: String {
        get {
            aiConfiguration.model
        }
        set {
            var updated = aiConfiguration
            updated.model = newValue
            dependencies.aiConfigurationStore.save(updated)
            aiConfiguration = updated
        }
    }

    func refreshAIConfiguration() {
        aiConfiguration = dependencies.aiConfigurationStore.load()
        refreshAPIKeyState()
    }

    func loadAPIKey() throws -> String {
        try dependencies.apiKeyStore.load() ?? ""
    }

    func saveAIConfiguration(
        _ configuration: AIProviderConfiguration,
        apiKey: String
    ) throws {
        let configuration = try configuration.validated()
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            try dependencies.apiKeyStore.delete()
        } else {
            try dependencies.apiKeyStore.save(trimmedKey)
        }
        dependencies.aiConfigurationStore.save(configuration)
        aiConfiguration = configuration
        refreshAPIKeyState()
    }

#if DEBUG
    /// A physical Debug launch receives the provider from the installer via
    /// process environment. Persist the complete pair once so a later launch
    /// from the iPhone icon cannot silently fall back to an older provider.
    @discardableResult
    func persistInjectedAIConfigurationIfPresent(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let configuration = AIConfigurationEnvironment.configuration(from: environment),
              let apiKey = environment[AIConfigurationEnvironmentKey.deepSeekAPIKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            return false
        }

        do {
            try saveAIConfiguration(configuration, apiKey: apiKey)
            return true
        } catch {
            // The injected values still remain available for this process;
            // do not print the key or turn a launch into a crash if the
            // device keychain is temporarily unavailable.
            return false
        }
    }
#endif

    func testAIConnection(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        try await dependencies.aiConnectionTester.test(
            configuration: configuration,
            apiKey: apiKey
        )
    }

    @discardableResult
    func reconcilePracticeSettings(
        validTopicIDs: Set<UUID>
    ) -> PracticeSettingsSnapshot {
        practiceSettings = dependencies.practiceSettingsStore.reconcile(
            validTopicIDs: validTopicIDs
        )
        return practiceSettings
    }

    func setPracticeTopicIDs(_ topicIDs: Set<UUID>) {
        var updated = practiceSettings
        updated.explicitTopicIDs = topicIDs
        dependencies.practiceSettingsStore.save(updated)
        practiceSettings = updated
    }

    func setIncludePracticed(_ includePracticed: Bool) {
        var updated = practiceSettings
        updated.includePracticed = includePracticed
        dependencies.practiceSettingsStore.save(updated)
        practiceSettings = updated
    }

    func refreshAPIKeyState() {
        apiKeyConfigured = (try? dependencies.apiKeyStore.load())??.isEmpty == false
    }

    func saveAPIKey(_ key: String) throws {
        try dependencies.apiKeyStore.save(key)
        refreshAPIKeyState()
    }

    func clearAPIKey() throws {
        try dependencies.apiKeyStore.delete()
        refreshAPIKeyState()
    }

}
