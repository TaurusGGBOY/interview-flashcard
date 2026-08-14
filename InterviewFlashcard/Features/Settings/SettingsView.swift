import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: \TopicRecord.createdAt) private var topics: [TopicRecord]
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section("功能设置") {
                NavigationLink {
                    AIServiceSettingsView()
                } label: {
                    SettingsNavigationRow(
                        title: "AI 服务",
                        systemImage: "sparkles",
                        summary: aiServiceSummary
                    )
                }
                .accessibilityIdentifier(AccessibilityID.settingsAIServiceRow)

                NavigationLink {
                    PracticeSettingsView()
                } label: {
                    SettingsNavigationRow(
                        title: "练习设置",
                        systemImage: "slider.horizontal.3",
                        summary: practiceSettingsSummary
                    )
                }
                .accessibilityIdentifier(AccessibilityID.settingsPracticeRow)
            }

            Section("安全与隐私") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("数据由你掌控", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("API Key 仅保存在设备的系统钥匙串中，不写入普通设置或诊断信息。题目整理和评分只会把你确认提交的文字发送给当前配置的 AI 服务。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("设置")
        .accessibilityIdentifier(AccessibilityID.settingsScreen)
        .task {
            environment.refreshAIConfiguration()
            environment.reconcilePracticeSettings(validTopicIDs: validTopicIDs)
        }
    }

    private var validTopicIDs: Set<UUID> {
        Set(topics.map(\.id))
    }

    private var aiServiceSummary: String {
        let provider = environment.aiConfiguration.provider.displayName
        let keyStatus = environment.apiKeyConfigured ? "密钥已配置" : "密钥未配置"
        return "\(provider) · \(keyStatus)"
    }

    private var practiceSettingsSummary: String {
        guard !validTopicIDs.isEmpty else { return "暂无主题" }
        let count = environment.practiceSettings
            .resolvedTopicIDs(validTopicIDs: validTopicIDs)
            .count
        if count == validTopicIDs.count {
            return "全部主题"
        }
        return "\(count)/\(validTopicIDs.count) 个主题"
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let systemImage: String
    let summary: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppEnvironment())
    .modelContainer(try! AppModelContainer.make(inMemory: true))
}
