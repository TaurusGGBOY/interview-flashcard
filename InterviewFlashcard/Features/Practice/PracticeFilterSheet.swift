import SwiftUI

struct PracticeTopicOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let activeCardCount: Int
}

struct PracticeFilterSelection: Equatable, Sendable {
    var selectedTopicIDs: Set<UUID>
    var includePracticed: Bool

    static let initial = Self(selectedTopicIDs: [], includePracticed: false)
}

struct PracticeFilterSheet: View {
    let topics: [PracticeTopicOption]
    let initialSelection: PracticeFilterSelection
    let onApply: (PracticeFilterSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PracticeFilterSelection

    init(
        topics: [PracticeTopicOption],
        initialSelection: PracticeFilterSelection,
        onApply: @escaping (PracticeFilterSelection) -> Void
    ) {
        self.topics = topics
        self.initialSelection = initialSelection
        self.onApply = onApply
        _draft = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(topics) { topic in
                        Toggle(isOn: topicBinding(for: topic.id)) {
                            HStack {
                                Text(topic.title)
                                Spacer()
                                Text("\(topic.activeCardCount)")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityIdentifier(PracticeAccessibilityID.topic(topic.id))
                    }
                } header: {
                    HStack {
                        Text("Topic")
                        Spacer()
                        Button("全选") {
                            draft.selectedTopicIDs = Set(topics.map(\.id))
                        }
                        .font(.subheadline.weight(.medium))
                    }
                } footer: {
                    Text("默认选择全部有效 Topic。")
                }

                Section {
                    Toggle("包含已练习题", isOn: $draft.includePracticed)
                        .accessibilityIdentifier(PracticeAccessibilityID.includePracticed)
                }
            }
            .navigationTitle("练习筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func topicBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { draft.selectedTopicIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    draft.selectedTopicIDs.insert(id)
                } else {
                    draft.selectedTopicIDs.remove(id)
                }
            }
        )
    }
}
