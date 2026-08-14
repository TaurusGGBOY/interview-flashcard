import SwiftData
import SwiftUI

struct PracticeSettingsView: View {
    var body: some View {
        Form {
            PracticeSettingsContent()
        }
        .navigationTitle("练习设置")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID.settingsPracticeScreen)
    }
}

struct PracticeSettingsContent: View {
    @Query(sort: \TopicRecord.createdAt) private var topics: [TopicRecord]
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            Section {
                if orderedTopics.isEmpty {
                    ContentUnavailableView(
                        "暂无主题",
                        systemImage: "rectangle.stack",
                        description: Text("导入或新建题目后，可在这里选择练习范围。")
                    )
                } else {
                    ForEach(orderedTopics) { topic in
                        Toggle(isOn: topicBinding(for: topic.id)) {
                            HStack {
                                Text(displayName(for: topic))
                                Spacer()
                                Text("\(activeCardCount(for: topic)) 题")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityIdentifier(PracticeAccessibilityID.topic(topic.id))
                    }
                }
            } header: {
                HStack {
                    Text("主题")
                    Spacer()
                    Button("全选") {
                        environment.setPracticeTopicIDs(validTopicIDs)
                    }
                    .textCase(nil)
                    .disabled(validTopicIDs.isEmpty)
                }
            } footer: {
                Text("首次使用默认包含当前全部主题。手动选择后，新建主题不会自动加入。")
            }

            Section {
                Toggle(
                    "包含已练习题",
                    isOn: Binding(
                        get: { environment.practiceSettings.includePracticed },
                        set: environment.setIncludePracticed
                    )
                )
                .accessibilityIdentifier(PracticeAccessibilityID.includePracticed)
            } header: {
                Text("题目范围")
            } footer: {
                Text("关闭时只抽取尚未练习的题目，更改会立即应用到练习页。")
            }

            Section("说明") {
                Label {
                    Text("至少选择一个有题目的主题，练习页才会生成题目。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.settingsPractice)
        .task {
            reconcileSettings()
        }
        .onChange(of: topics.map(\.id)) { _, _ in
            reconcileSettings()
        }
    }

    private var orderedTopics: [TopicRecord] {
        topics.sorted { lhs, rhs in
            if lhs.systemKind == .others, rhs.systemKind != .others { return true }
            if lhs.systemKind != .others, rhs.systemKind == .others { return false }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : comparison == .orderedAscending
        }
    }

    private var validTopicIDs: Set<UUID> {
        Set(topics.map(\.id))
    }

    private func topicBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                environment.practiceSettings
                    .resolvedTopicIDs(validTopicIDs: validTopicIDs)
                    .contains(id)
            },
            set: { isSelected in
                var selected = environment.practiceSettings
                    .resolvedTopicIDs(validTopicIDs: validTopicIDs)
                if isSelected {
                    selected.insert(id)
                } else {
                    selected.remove(id)
                }
                environment.setPracticeTopicIDs(selected)
            }
        )
    }

    private func reconcileSettings() {
        environment.reconcilePracticeSettings(validTopicIDs: validTopicIDs)
    }

    private func activeCardCount(for topic: TopicRecord) -> Int {
        topic.cards.lazy.filter { !$0.isTrashed }.count
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }
}

#Preview {
    NavigationStack {
        PracticeSettingsView()
    }
    .environment(AppEnvironment())
    .modelContainer(try! AppModelContainer.make(inMemory: true))
}
