import Foundation
import SwiftData

/// The public seam between the thin application target and the feature
/// framework. Keeping composition here lets the XCTest host use a separate,
/// empty application instead of booting the production SwiftData scene.
@MainActor
public final class AppRuntime {
    public let modelContainer: ModelContainer
    public let environment: AppEnvironment

    public init() throws {
        modelContainer = try AppModelContainer.make()

        let launchOptions = AppEnvironment.LaunchOptions.current()
        let apiKeyStore = KeychainAPIKeyStore()
#if DEBUG
        // Persist only the provider choice, never the credential. This keeps a
        // simulator/app restart (which has no launch arguments) on the same
        // provider while the key itself remains in Keychain.
        UserDefaults.standard.set(
            launchOptions.aiProvider.rawValue,
            forKey: AppEnvironment.SettingsKey.aiProvider
        )
        if launchOptions.aiProvider == .deepseek,
           let environmentKey = ProcessInfo.processInfo.environment["INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY"],
           !environmentKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // The development launcher passes this value through SIMCTL_CHILD_*
            // so a real smoke run can populate the simulator Keychain without
            // putting the secret in source, logs, or diagnostics.
            try? apiKeyStore.save(environmentKey)
        }
#endif
        let aiClient: any AIClient
        switch launchOptions.aiProvider {
        case .stub:
            let mode = StubAIClient.Mode(rawValue: launchOptions.stubMode) ?? .success
            aiClient = RetryingAIClient(
                base: StubAIClient(mode: mode),
                retryDelayNanoseconds: 0
            )
        case .deepseek:
            let model = UserDefaults.standard.string(forKey: AppEnvironment.SettingsKey.deepSeekModel)
                ?? "deepseek-v4-flash"
            let client = DeepSeekAIClient(
                configuration: .init(model: model),
                apiKeyStore: apiKeyStore
            )
            aiClient = RetryingAIClient(base: client)
        }

        environment = AppEnvironment(
            launchOptions: launchOptions,
            dependencies: .init(
                now: { Date() },
                aiClient: aiClient,
                apiKeyStore: apiKeyStore
            )
        )
    }

    public func bootstrap() {
        let context = modelContainer.mainContext
        do {
            environment.refreshAPIKeyState()
            try AppModelContainer.bootstrapOthers(
                context: context,
                now: environment.dependencies.now()
            )
            #if DEBUG
            if let fixture = environment.launchOptions.seedFixture {
                try AcceptanceSeeder.seed(named: fixture, context: context)
            }
            #endif
            try DiagnosticStateExporter(
                isEnabled: environment.launchOptions.diagnosticsEnabled
            ).export(from: context)
            let importer = ImportCoordinator(
                context: context,
                aiClient: environment.dependencies.aiClient,
                diagnostics: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled),
                now: environment.dependencies.now
            )
            let processing = AnswerProcessingService(
                aiClient: environment.dependencies.aiClient,
                now: environment.dependencies.now,
                diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
            )
            Task { @MainActor in
                await LaunchRecoveryCoordinator(importer: importer, processing: processing).resume(context: context)
            }
        } catch {
            assertionFailure("App bootstrap failed: \(error.localizedDescription)")
        }
    }
}
