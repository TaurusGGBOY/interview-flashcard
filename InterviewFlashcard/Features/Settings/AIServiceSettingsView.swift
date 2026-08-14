import SwiftUI

struct AISettingsDraft: Equatable {
    var provider: AIProviderKind
    var baseURL: String
    var model: String
    var apiKey: String

    init(configuration: AIProviderConfiguration, apiKey: String) {
        provider = configuration.provider
        baseURL = configuration.baseURL
        model = configuration.model
        self.apiKey = apiKey
    }

    var canSave: Bool {
        (try? validatedConfiguration()) != nil
    }

    var canTest: Bool {
        canSave && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func selectProvider(_ provider: AIProviderKind) {
        let defaults = provider.defaultConfiguration
        self.provider = provider
        baseURL = defaults.baseURL
        model = defaults.model
        apiKey = ""
    }

    func validatedConfiguration() throws -> AIProviderConfiguration {
        try AIProviderConfiguration(
            provider: provider,
            baseURL: baseURL,
            model: model
        ).validated()
    }

    static func connectionSuccessMessage(reply: String) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return "连接成功：\(String(trimmed.prefix(80)))"
    }

    static func connectionErrorMessage(for error: Error) -> String {
        if let configurationError = error as? AIConfigurationError {
            return configurationError.localizedDescription
        }
        guard let error = error as? AIError else {
            return "连接失败，请检查网络或服务配置"
        }
        switch error {
        case .missingAPIKey:
            return "请输入 API Key"
        case .unauthorized:
            return "认证失败，请检查 API Key"
        case .rateLimited:
            return "请求过于频繁，请稍后重试"
        case .httpStatus(let status) where status == 400 || status == 404:
            return "模型或接口地址不可用"
        case .transport(let code) where code == String(describing: URLError.Code.timedOut):
            return "连接超时，请检查网络或服务地址"
        case .invalidResponse, .malformedStructuredResponse, .truncatedResponse:
            return "服务已响应，但返回格式无法识别"
        case .transientHTTPStatus, .httpStatus, .transport, .processingPaused:
            return "连接失败，请检查网络或服务配置"
        }
    }
}

struct AIServiceSettingsView: View {
    var body: some View {
        Form {
            AIServiceSettingsContent()
        }
        .navigationTitle("AI 服务")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID.settingsAIServiceScreen)
    }
}

struct AIServiceSettingsContent: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var draft = AISettingsDraft(
        configuration: AIProviderKind.openAICompatible.defaultConfiguration,
        apiKey: ""
    )
    @State private var message: String?
    @State private var messageIsSuccess = false
    @State private var isTesting = false
    @State private var didLoad = false
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        Group {
            Section("服务商") {
                Picker("类型", selection: providerBinding) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier(AccessibilityID.settingsAIProvider)
            }

            Section {
                TextField("Base URL", text: $draft.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier(AccessibilityID.settingsAIBaseURL)

                TextField("模型", text: $draft.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(AccessibilityID.settingsModel)

                SecureField("API Key", text: $draft.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .accessibilityIdentifier(AccessibilityID.settingsAPIKey)
            } header: {
                Text("连接")
            } footer: {
                Text("Base URL、模型和 API Key 均可编辑。切换服务商会填入对应的默认配置。")
            }

            Section("操作") {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!draft.canTest || isTesting)
                .accessibilityIdentifier(AccessibilityID.settingsAITestConnection)

                Button("保存设置") {
                    save()
                }
                .disabled(!draft.canSave || isTesting)
                .accessibilityIdentifier(AccessibilityID.settingsAISave)

                if let message {
                    Label(
                        message,
                        systemImage: messageIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(messageIsSuccess ? .green : .secondary)
                    .accessibilityIdentifier(AccessibilityID.settingsAIMessage)
                }
            }

            Section("安全") {
                Label {
                    Text("API Key 保存在系统钥匙串中。测试连接只使用当前页面的草稿，不会自动保存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.settingsAIService)
        .task {
            loadDraftIfNeeded()
        }
        .onDisappear {
            testTask?.cancel()
        }
    }

    private var providerBinding: Binding<AIProviderKind> {
        Binding(
            get: { draft.provider },
            set: { provider in
                guard provider != draft.provider else { return }
                draft.selectProvider(provider)
                message = nil
                messageIsSuccess = false
            }
        )
    }

    private func loadDraftIfNeeded() {
        guard !didLoad else { return }
        environment.refreshAIConfiguration()
        let apiKey = (try? environment.loadAPIKey()) ?? ""
        draft = AISettingsDraft(configuration: environment.aiConfiguration, apiKey: apiKey)
        didLoad = true
    }

    private func save() {
        do {
            try environment.saveAIConfiguration(
                draft.validatedConfiguration(),
                apiKey: draft.apiKey
            )
            message = "设置已保存并立即生效"
            messageIsSuccess = true
        } catch {
            message = AISettingsDraft.connectionErrorMessage(for: error)
            messageIsSuccess = false
        }
    }

    private func testConnection() {
        testTask?.cancel()
        isTesting = true
        message = nil
        messageIsSuccess = false
        let currentDraft = draft
        testTask = Task { @MainActor in
            defer { isTesting = false }
            do {
                let reply = try await environment.testAIConnection(
                    configuration: currentDraft.validatedConfiguration(),
                    apiKey: currentDraft.apiKey
                )
                try Task.checkCancellation()
                message = AISettingsDraft.connectionSuccessMessage(reply: reply)
                messageIsSuccess = true
            } catch is CancellationError {
                return
            } catch {
                message = AISettingsDraft.connectionErrorMessage(for: error)
                messageIsSuccess = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        AIServiceSettingsView()
    }
    .environment(AppEnvironment())
}
