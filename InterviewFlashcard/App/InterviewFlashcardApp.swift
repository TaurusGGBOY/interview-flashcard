import SwiftData
import SwiftUI

@main
struct InterviewFlashcardApp: App {
    private let modelContainer: ModelContainer
    @State private var environment: AppEnvironment
    @State private var didBootstrap = false

    init() {
        do {
            modelContainer = try AppModelContainer.make()
        } catch {
            fatalError("Unable to initialize local persistence: \(error.localizedDescription)")
        }
        let launchOptions = AppEnvironment.LaunchOptions.current()
        let apiKeyStore = KeychainAPIKeyStore()
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
                ?? "deepseek-chat"
            let client = DeepSeekAIClient(
                configuration: .init(model: model),
                apiKeyStore: apiKeyStore
            )
            aiClient = RetryingAIClient(base: client)
        }
        _environment = State(
            initialValue: AppEnvironment(
                launchOptions: launchOptions,
                dependencies: .init(
                    now: { Date() },
                    aiClient: aiClient,
                    apiKeyStore: apiKeyStore
                )
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .task {
                    guard !didBootstrap else { return }
                    didBootstrap = true
                    bootstrapLocalState()
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func bootstrapLocalState() {
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
