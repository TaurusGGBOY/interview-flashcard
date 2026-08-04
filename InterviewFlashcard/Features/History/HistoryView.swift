import SwiftData
import SwiftUI

enum HistoryAccessibilityID {
    static let screen = "history.screen"
    static let topicFilter = "history.topic-filter"
    static let row = "history.row"
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \.submittedAt, order: .reverse) private var attempts: [AnswerAttemptRecord]
    @Query(sort: \.name) private var topics: [TopicRecord]
    @State private var selectedTopicID: UUID?

    private var visibleAttempts: [AnswerAttemptRecord] {
        attempts.filter { attempt in
            guard attempt.question.trashedAt == nil else { return false }
            return selectedTopicID == nil || attempt.question.topic.id == selectedTopicID
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Topic", selection: $selectedTopicID) {
                    Text("全部 Topic").tag(Optional<UUID>.none)
                    ForEach(topics.sorted(by: TopicService.libraryOrder), id: \.id) { topic in
                        Text(topic.systemKind == .others ? "待分类（Others）" : topic.name).tag(Optional(topic.id))
                    }
                }
                .accessibilityIdentifier(HistoryAccessibilityID.topicFilter)
            }

            Section("回答历史（\(visibleAttempts.count)）") {
                if visibleAttempts.isEmpty {
                    ContentUnavailableView("还没有回答历史", systemImage: "clock.arrow.circlepath")
                } else {
                    ForEach(visibleAttempts, id: \.id) { attempt in
                        NavigationLink {
                            AttemptDetailView(attempt: attempt)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(attempt.questionTextSnapshot)
                                    .lineLimit(2)
                                HStack {
                                    Text(attempt.submittedAt, format: .dateTime)
                                    Text(attempt.inputMode == .voice ? "语音" : "文字")
                                    Spacer()
                                    if let evaluation = attempt.evaluations.max(by: { $0.createdAt < $1.createdAt }), let score = evaluation.totalScore {
                                        Text("\(score) 分")
                                            .fontWeight(.semibold)
                                    } else {
                                        Text(statusText(attempt.processingStatus))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("\(HistoryAccessibilityID.row).\(attempt.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle("历史")
        .accessibilityIdentifier(HistoryAccessibilityID.screen)
    }

    private func statusText(_ status: AttemptProcessingStatus) -> String {
        switch status {
        case .saved: "待处理"
        case .polishing: "润色中"
        case .evaluating: "评分中"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }
}
