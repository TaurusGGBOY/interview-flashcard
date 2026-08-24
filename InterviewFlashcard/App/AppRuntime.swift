import Foundation
import SwiftData

/// The public seam between the thin application target and the feature
/// framework. Keeping composition here lets the XCTest host use a separate,
/// empty application instead of booting the production SwiftData scene.
@MainActor
public final class AppRuntime {
    public static let backgroundImportTaskIdentifier = "com.gaoguobin.InterviewFlashcard.import"

    public let modelContainer: ModelContainer
    public let environment: AppEnvironment
    public let externalDocumentImportInbox: ExternalDocumentImportInbox

    private var importCoordinator: ImportCoordinator?
    private var answerProcessing: AnswerProcessingService?
    private var didPrepareServices = false
    private var didStartRecovery = false
    private var didStartAcceptanceImport = false

    public init() throws {
        modelContainer = try AppModelContainer.make()

        let launchOptions = AppEnvironment.LaunchOptions.current()
        let apiKeyStore: any APIKeyStore = EnvironmentBackedAPIKeyStore()
        let configurationStore = UserDefaultsAIConfigurationStore()
        let practiceSettingsStore = UserDefaultsPracticeSettingsStore()
        let transport = URLSessionAIHTTPTransport()
        let aiClient: any AIClient
        switch launchOptions.aiProvider {
        case .stub:
            let mode = StubAIClient.Mode(rawValue: launchOptions.stubMode) ?? .success
            aiClient = RetryingAIClient(
                base: StubAIClient(mode: mode),
                retryDelayNanoseconds: 0
            )
        case .deepseek:
            let client = DynamicAIClientRouter(
                configurationStore: configurationStore,
                apiKeyStore: apiKeyStore,
                transport: transport
            )
            aiClient = RetryingAIClient(base: client)
        }

        environment = AppEnvironment(
            launchOptions: launchOptions,
            dependencies: .init(
                now: { Date() },
                aiClient: aiClient,
                apiKeyStore: apiKeyStore,
                aiConfigurationStore: configurationStore,
                aiConnectionTester: AIConnectionTester(transport: transport),
                practiceSettingsStore: practiceSettingsStore
            )
        )
        externalDocumentImportInbox = ExternalDocumentImportInbox()
    }

    public func bootstrap() {
        do {
            try prepareServices()
            guard !didStartRecovery else { return }
            didStartRecovery = true

            let context = modelContainer.mainContext
            let importer = importCoordinator
            let processing = answerProcessing
            Task { @MainActor in
                await LaunchRecoveryCoordinator(importer: importer, processing: processing).resume(context: context)
#if DEBUG
                await self.startJSONInboxImportIfRequested()
                await self.startAcceptanceImportIfRequested()
#endif
            }
        } catch {
            assertionFailure("App bootstrap failed: \(error.localizedDescription)")
        }
    }

    /// Runs persisted import work from an iOS BGProcessingTask.
    ///
    /// The coordinator checkpoints each chunk before and after its network
    /// request. If iOS expires this task, the next invocation can continue
    /// from the last persisted chunk instead of starting over.
    public func processPendingImports() async -> Bool {
        do {
            try prepareServices()
        } catch {
            return false
        }

        guard let importer = importCoordinator else { return false }
        let context = modelContainer.mainContext
        let runs = (try? context.fetch(FetchDescriptor<ImportRunRecord>())) ?? []

        for run in runs where Self.isBackgroundResumable(run.status) {
            guard !Task.isCancelled else { return false }
            try? await importer.continueRun(id: run.id)
        }

        guard !Task.isCancelled else { return false }
        let remainingRuns = (try? context.fetch(FetchDescriptor<ImportRunRecord>())) ?? []
        return !remainingRuns.contains(where: { Self.isBackgroundResumable($0.status) })
    }

    private func prepareServices() throws {
        guard !didPrepareServices else { return }

        let context = modelContainer.mainContext
#if DEBUG
        _ = environment.persistInjectedAIConfigurationIfPresent()
#endif
        environment.refreshAPIKeyState()
        try AppModelContainer.bootstrapOthers(
            context: context,
            now: environment.dependencies.now()
        )
        try TopicNameHygiene.repair(
            context: context,
            now: environment.dependencies.now()
        )
        try QuestionNumberingService().backfillIfNeeded(context: context)
        try context.save()
        #if DEBUG
        if let fixture = environment.launchOptions.seedFixture {
            try AcceptanceSeeder.seed(named: fixture, context: context)
        }
        try writeAcceptanceJSONFixtureIfRequested()
        #endif
        try DiagnosticStateExporter(
            isEnabled: environment.launchOptions.diagnosticsEnabled
        ).export(from: context)

        let importer = ImportCoordinator(
            context: context,
            aiClient: environment.dependencies.aiClient,
            diagnostics: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled),
            singlePassLLMImport: false,
            refinementBatchSize: 4,
            now: environment.dependencies.now
        )
        let processing = AnswerProcessingService(
            aiClient: environment.dependencies.aiClient,
            now: environment.dependencies.now,
            diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
        )
        importCoordinator = importer
        answerProcessing = processing
        environment.importCoordinator = importer
        didPrepareServices = true
    }

#if DEBUG
    private func startJSONInboxImportIfRequested() async {
        guard environment.launchOptions.jsonInboxImportRequested else { return }

        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            guard let enumerator = FileManager.default.enumerator(
                at: documentsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw CocoaError(.fileReadUnknown)
            }
            let urls = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard !urls.isEmpty else {
                throw CocoaError(.fileNoSuchFile)
            }

            let drafts = try urls.map { url in
                try JSONQuestionImportParser.parse(
                    data: Data(contentsOf: url, options: .mappedIfSafe),
                    fileName: url.lastPathComponent
                )
            }
            _ = try JSONQuestionImportService(
                now: environment.dependencies.now,
                diagnosticExporter: DiagnosticStateExporter(
                    isEnabled: environment.launchOptions.diagnosticsEnabled
                )
            ).confirm(drafts: drafts, context: modelContainer.mainContext)
        } catch {
            assertionFailure("JSON inbox import failed: \(error.localizedDescription)")
        }
    }

    private func writeAcceptanceJSONFixtureIfRequested() throws {
        guard let requestedName = environment.launchOptions.acceptanceJSONFixtureFile else {
            return
        }
        let fileName = URL(fileURLWithPath: requestedName).lastPathComponent
        guard fileName == requestedName, fileName.lowercased().hasSuffix(".json") else {
            return
        }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        let fixture = """
        {
          "formatVersion": 1,
          "questions": [
            {
              "question": "JSON 验收题目：已有 Topic",
              "topic": "后端",
              "answer": "第一行满分答案。\\n第二行用于验证多行内容。"
            },
            {
              "question": "JSON 验收题目：重复题",
              "topic": "JSON 新主题",
              "answer": "重复题的第一份满分答案。"
            },
            {
              "question": "JSON 验收题目：重复题",
              "topic": "json新主题",
              "answer": "重复题的第二份满分答案。"
            }
          ]
        }
        """
        try Data(fixture.utf8).write(
            to: documentsURL.appendingPathComponent(fileName),
            options: .atomic
        )
    }

    private func startAcceptanceImportIfRequested() async {
        guard !didStartAcceptanceImport,
              let importer = importCoordinator else {
            return
        }
        didStartAcceptanceImport = true

        if let runID = environment.launchOptions.acceptanceConfirmRunID {
            let startedAt = Date()
            do {
                try importer.confirmImport(id: runID)
                print(
                    "ACCEPTANCE_IMPORT confirmed runID=\(runID.uuidString) " +
                    "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))"
                )
            } catch {
                print(
                    "ACCEPTANCE_IMPORT confirm_failed runID=\(runID.uuidString) " +
                    "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt))) " +
                    "error=\(error.localizedDescription)"
                )
            }
            return
        }

        if let runID = environment.launchOptions.acceptanceContinueRunID {
            let startedAt = Date()
            do {
                try await importer.continueRun(id: runID)
                print(
                    "ACCEPTANCE_IMPORT continued runID=\(runID.uuidString) " +
                    "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))"
                )
            } catch {
                print(
                    "ACCEPTANCE_IMPORT continue_failed runID=\(runID.uuidString) " +
                    "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt))) " +
                    "error=\(error.localizedDescription)"
                )
            }
            return
        }

        guard let relativeOrAbsolutePath = environment.launchOptions.acceptanceImportFile else {
            return
        }

        let fileManager = FileManager.default
        let fileURL: URL
        if relativeOrAbsolutePath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: relativeOrAbsolutePath)
        } else {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            fileURL = documentsURL.appendingPathComponent(relativeOrAbsolutePath)
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("ACCEPTANCE_IMPORT missing_file=\(fileURL.lastPathComponent)")
            return
        }

        let startedAt = Date()
        do {
            let runIDs = try await importer.start(urls: [fileURL])
            print(
                "ACCEPTANCE_IMPORT queued file=\(fileURL.lastPathComponent) " +
                "runID=\(runIDs.first?.uuidString ?? "none")"
            )
        } catch {
            print(
                "ACCEPTANCE_IMPORT failed file=\(fileURL.lastPathComponent) " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt))) " +
                "error=\(error.localizedDescription)"
            )
        }
    }
#endif

    private static func isBackgroundResumable(_ status: ImportRunStatus) -> Bool {
        switch status {
        case .queued, .chunking, .decomposing, .refining, .activating:
            true
        case .ready, .active, .failed:
            false
        }
    }
}
