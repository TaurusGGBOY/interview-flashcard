import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    enum SettingsKey {
        static let deepSeekModel = "settings.deepseek.model"
    }

    struct LaunchOptions: Equatable, Sendable {
        enum AIProvider: String, Sendable {
            case stub
            case deepseek
        }

        enum SpeechCapabilityOverride: String, Sendable {
            case automatic
            case supported
            case fixtureSupported = "fixture-supported"
            case unsupported
            case denied
            case permissionDenied = "permission-denied"
        }

        var diagnosticsEnabled: Bool
        var aiProvider: AIProvider
        var stubMode: String
        var speechCapability: SpeechCapabilityOverride
        var seedFixture: String?
        var randomSeed: UInt64?

        static func current(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> LaunchOptions {
            let valueAfter: (String) -> String? = { flag in
                guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                    return nil
                }
                return arguments[index + 1]
            }

            #if DEBUG
            let provider = AIProvider(rawValue: valueAfter("-IFAIProvider") ?? "")
                ?? AIProvider(rawValue: environment["IF_DEFAULT_AI_PROVIDER"] ?? "")
                ?? .stub
            let speech = SpeechCapabilityOverride(rawValue: valueAfter("-IFSpeechCapability") ?? "") ?? .automatic
            return LaunchOptions(
                diagnosticsEnabled: valueAfter("-IFDiagnosticsEnabled") == "YES",
                aiProvider: provider,
                stubMode: valueAfter("-IFStubMode") ?? "success",
                speechCapability: speech,
                seedFixture: valueAfter("-IFSeedFixture"),
                randomSeed: valueAfter("-IFRandomSeed").flatMap(UInt64.init)
            )
            #else
            return LaunchOptions(
                diagnosticsEnabled: false,
                aiProvider: .deepseek,
                stubMode: "success",
                speechCapability: .automatic,
                seedFixture: nil,
                randomSeed: nil
            )
            #endif
        }
    }

    struct Dependencies: Sendable {
        typealias MakeAudioRecorder = @Sendable () -> any AudioRecording

        var now: @Sendable () -> Date
        var aiClient: any AIClient
        var apiKeyStore: any APIKeyStore
        var speechTranscriber: any SpeechTranscribing
        var makeAudioRecorder: MakeAudioRecorder

        init(
            now: @escaping @Sendable () -> Date,
            aiClient: any AIClient,
            apiKeyStore: any APIKeyStore,
            speechTranscriber: any SpeechTranscribing = AppleSpeechTranscriber(),
            makeAudioRecorder: @escaping MakeAudioRecorder = { M4AAudioRecorder() }
        ) {
            self.now = now
            self.aiClient = aiClient
            self.apiKeyStore = apiKeyStore
            self.speechTranscriber = speechTranscriber
            self.makeAudioRecorder = makeAudioRecorder
        }

        static let live = Dependencies(
            now: { Date() },
            aiClient: StubAIClient(),
            apiKeyStore: KeychainAPIKeyStore(),
            speechTranscriber: AppleSpeechTranscriber(),
            makeAudioRecorder: { M4AAudioRecorder() }
        )
    }

    let launchOptions: LaunchOptions
    let dependencies: Dependencies
    private(set) var apiKeyConfigured = false

    init(
        launchOptions: LaunchOptions = .current(),
        dependencies: Dependencies = .live
    ) {
        self.launchOptions = launchOptions
        self.dependencies = dependencies
    }

    var configuredModel: String {
        get {
            UserDefaults.standard.string(forKey: SettingsKey.deepSeekModel)
                ?? "deepseek-chat"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: SettingsKey.deepSeekModel)
        }
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

    var resolvedSpeechTranscriber: any SpeechTranscribing {
        switch launchOptions.speechCapability {
        case .automatic:
            dependencies.speechTranscriber
        case .supported, .fixtureSupported:
            FixtureSpeechTranscriber(capability: .available)
        case .unsupported:
            FixtureSpeechTranscriber(
                capability: .unavailable(.onDeviceRecognitionUnsupported)
            )
        case .denied:
            FixtureSpeechTranscriber(capability: .unavailable(.authorizationDenied))
        case .permissionDenied:
            FixtureSpeechTranscriber(
                capability: .authorizationRequired,
                transcriptionError: .unavailable(.authorizationDenied)
            )
        }
    }

    func makeResolvedAudioRecorder() -> any AudioRecording {
        switch launchOptions.speechCapability {
        case .automatic:
            dependencies.makeAudioRecorder()
        case .supported, .fixtureSupported, .unsupported, .denied, .permissionDenied:
            FixtureAudioRecorder()
        }
    }
}
