import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var apiKey = ""
    @State private var model = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("DeepSeek") {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(AccessibilityID.settingsAPIKey)

                TextField("模型", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(AccessibilityID.settingsModel)

                HStack {
                    Label(
                        environment.apiKeyConfigured ? "API Key 已配置" : "API Key 未配置",
                        systemImage: environment.apiKeyConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(environment.apiKeyConfigured ? .green : .secondary)
                    Spacer()
                    Button("保存") {
                        save()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier(AccessibilityID.settingsSaveKey)
                }

                Button("清除 API Key", role: .destructive) {
                    clear()
                }
                .disabled(!environment.apiKeyConfigured)
                .accessibilityIdentifier(AccessibilityID.settingsClearKey)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.settingsMessage)
                }
            }

            Section("隐私") {
                Text("Markdown 和你确认提交的文字回答可能会发送给 DeepSeek 用于题目整理、作答润色和评分。语音音频只保存在本机，永不上传；语音必须先在设备端完成本地转写。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .accessibilityIdentifier(AccessibilityID.settingsScreen)
        .task {
            model = environment.configuredModel
            environment.refreshAPIKeyState()
        }
        .onChange(of: model) { _, newValue in
            environment.configuredModel = newValue
        }
    }

    private func save() {
        do {
            try environment.saveAPIKey(apiKey)
            apiKey = ""
            message = "已保存（仅存储在本机 Keychain）"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }

    private func clear() {
        do {
            try environment.clearAPIKey()
            message = "已清除 API Key"
        } catch {
            message = "清除失败：\(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment())
}
