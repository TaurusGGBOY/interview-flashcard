import XCTest

final class AppShellTests: XCTestCase {
    func testRootTabsHaveStableChineseTitles() {
        XCTAssertEqual(AppRoute.rootTabs.map(\.title), ["练习", "题库", "历史", "统计", "设置"])
        XCTAssertEqual(Set(AppRoute.rootTabs.map(\.accessibilityID)).count, 5)
    }

    func testJSONImportAccessibilityIdentifiersAreStableAndDistinct() {
        let identifiers = [
            ImportAccessibilityID.importButton,
            ImportAccessibilityID.jsonImportButton,
            ImportAccessibilityID.jsonTemplateButton,
            ImportAccessibilityID.jsonTemplateScreen,
            ImportAccessibilityID.jsonTemplateCode,
            ImportAccessibilityID.jsonTemplateCopyButton,
            ImportAccessibilityID.jsonWorkingIndicator,
            ImportAccessibilityID.jsonPreviewScreen,
            ImportAccessibilityID.jsonConfirmButton,
            ImportAccessibilityID.jsonValidationScreen,
        ]

        XCTAssertEqual(ImportAccessibilityID.importButton, "import.markdown.button")
        XCTAssertEqual(ImportAccessibilityID.jsonImportButton, "import.json.button")
        XCTAssertEqual(ImportAccessibilityID.jsonTemplateButton, "import.json.template-button")
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testColdLaunchStartsWithAnUnpracticedFeedAndCanRouteGlobalEmptyToLibrary() {
        let firstTopicID = UUID(uuidString: "73000000-0000-0000-0000-000000000001")!
        let state = PracticeView.initialFeedState(topicIDs: [firstTopicID])

        XCTAssertEqual(state.selectedTopicIDs, [firstTopicID])
        XCTAssertFalse(state.includePracticed)
        XCTAssertEqual(RootTabView.defaultSelection, .practice)
        XCTAssertEqual(RootTabView.globalEmptyDestination, .library)
    }

    func testAnswerEditorSubmissionRoutingUsesQuestionIDNotAttemptID() {
        let questionID = UUID(uuidString: "74000000-0000-0000-0000-000000000001")!
        let attemptID = UUID(uuidString: "75000000-0000-0000-0000-000000000001")!

        XCTAssertEqual(
            AnswerEditorView.submittedQuestionID(questionID: questionID, attemptID: attemptID),
            questionID
        )
        XCTAssertNotEqual(
            AnswerEditorView.submittedQuestionID(questionID: questionID, attemptID: attemptID),
            attemptID
        )
    }

    func testLibraryQuestionLaunchesPracticeOnTheCardBack() {
        let questionID = UUID(uuidString: "74100000-0000-0000-0000-000000000001")!
        let request = PracticeLaunchRequest(questionID: questionID, startInAnswer: true)

        XCTAssertEqual(request.questionID, questionID)
        XCTAssertTrue(request.startInAnswer)
    }

    func testExtractionPromptRejectsBareConceptsAndPinsKubernetesTopic() {
        let prompt = PromptCatalog.systemPrompt(
            for: .decompose,
            availableTopicNames: ["Others", "Kubernetes"]
        )

        XCTAssertTrue(prompt.contains("Never create a candidate from a bare noun"))
        XCTAssertTrue(prompt.contains("Kubernetes/K8S"))
        XCTAssertEqual(PromptCatalog.decomposeVersion, "decompose-extraction-v6")
    }

    @MainActor
    func testDebugLaunchOptionsParseAcceptanceArguments() {
        let options = AppEnvironment.LaunchOptions.current(arguments: [
            "InterviewFlashcard",
            "-IFDiagnosticsEnabled", "YES",
            "-IFAIProvider", "stub",
            "-IFStubMode", "transient-failure",
            "-IFSeedFixture", "empty",
            "-IFRandomSeed", "42",
            "-IFAcceptanceJSONFixtureFile", "acceptance-json-import.json",
            "-IFAcceptanceConfirmRunID", "76000000-0000-0000-0000-000000000001",
            "-IFKeepAwake", "YES",
        ])

        #if DEBUG
        XCTAssertTrue(options.diagnosticsEnabled)
        XCTAssertEqual(options.aiProvider, .stub)
        XCTAssertEqual(options.stubMode, "transient-failure")
        XCTAssertEqual(options.seedFixture, "empty")
        XCTAssertEqual(options.randomSeed, 42)
        XCTAssertEqual(options.acceptanceJSONFixtureFile, "acceptance-json-import.json")
        XCTAssertEqual(
            options.acceptanceConfirmRunID,
            UUID(uuidString: "76000000-0000-0000-0000-000000000001")
        )
        XCTAssertTrue(options.keepAwakeWhileConnected)
        #else
        XCTAssertFalse(options.diagnosticsEnabled)
        XCTAssertEqual(options.aiProvider, .deepseek)
        XCTAssertNil(options.seedFixture)
        #endif
    }

    @MainActor
    func testDebugLaunchOptionsDefaultToDeepSeekWithoutExplicitProvider() {
        let suiteName = "AppShellTests.default-provider"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let options = AppEnvironment.LaunchOptions.current(
            arguments: ["InterviewFlashcard"],
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertEqual(options.aiProvider, .deepseek)
        #else
        XCTAssertEqual(options.aiProvider, .deepseek)
        #endif
    }

    @MainActor
    func testDebugIconLaunchReusesPersistedProviderWithoutArguments() {
        let suiteName = "AppShellTests.persisted-provider"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            AppEnvironment.LaunchOptions.AIProvider.deepseek.rawValue,
            forKey: AppEnvironment.SettingsKey.aiProvider
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let options = AppEnvironment.LaunchOptions.current(
            arguments: ["InterviewFlashcard"],
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertEqual(options.aiProvider, .deepseek)
        #else
        XCTAssertEqual(options.aiProvider, .deepseek)
        #endif
    }

    @MainActor
    func testDebugIconLaunchNeverReusesPersistedStubProvider() {
        let suiteName = "AppShellTests.persisted-stub-provider"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            AppEnvironment.LaunchOptions.AIProvider.stub.rawValue,
            forKey: AppEnvironment.SettingsKey.aiProvider
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let options = AppEnvironment.LaunchOptions.current(
            arguments: ["InterviewFlashcard"],
            environment: [:],
            userDefaults: defaults
        )

        #if DEBUG
        XCTAssertEqual(options.aiProvider, .deepseek)
        #else
        XCTAssertEqual(options.aiProvider, .deepseek)
        #endif
    }

    @MainActor
    func testInjectedDebugProviderAndKeyArePersistedForFutureIconLaunches() throws {
        let configurationStore = InMemoryAIConfigurationStore(
            configuration: AIProviderKind.openAICompatible.defaultConfiguration
        )
        let keyStore = InMemoryAPIKeyStore(key: "old-provider-key")
        let environment = AppEnvironment(
            launchOptions: .current(arguments: ["InterviewFlashcard"], environment: [:]),
            dependencies: .init(
                now: { Date() },
                aiClient: StubAIClient(),
                apiKeyStore: keyStore,
                aiConfigurationStore: configurationStore,
                aiConnectionTester: TestAIConnectionTester()
            )
        )
        let openCodeEnvironment = [
            AIConfigurationEnvironmentKey.deepSeekBaseURL: "https://opencode.ai/zen/go",
            AIConfigurationEnvironmentKey.deepSeekModel: "deepseek-v4-flash",
            AIConfigurationEnvironmentKey.deepSeekProvider: "openai",
            AIConfigurationEnvironmentKey.deepSeekAPIKey: "opencode-key",
        ]
        let injectedConfiguration = AIProviderConfiguration(
            provider: .openAI,
            baseURL: "https://opencode.ai/zen/go",
            model: "deepseek-v4-flash"
        )

#if DEBUG
        XCTAssertTrue(environment.persistInjectedAIConfigurationIfPresent(environment: openCodeEnvironment))
        XCTAssertEqual(environment.aiConfiguration, injectedConfiguration)
        XCTAssertEqual(configurationStore.load(), injectedConfiguration)
        XCTAssertEqual(try keyStore.load(), "opencode-key")
        #else
        XCTAssertFalse(environment.persistInjectedAIConfigurationIfPresent(environment: openCodeEnvironment))
        #endif
    }
}

private struct TestAIConnectionTester: AIConnectionTesting {
    func test(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        "ok"
    }
}
