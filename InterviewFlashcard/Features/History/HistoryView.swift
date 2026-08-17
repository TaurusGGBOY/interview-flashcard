import SwiftData
import SwiftUI

enum HistoryAccessibilityID {
    static let screen = "history.screen"
    static let topicFilter = "history.topic-filter"
    static let search = "history.search"
    static let row = "history.row"
    static let detail = "history.detail.sheet"
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AnswerAttemptRecord.submittedAt, order: .reverse) private var attempts: [AnswerAttemptRecord]
    @Query(sort: \TopicRecord.name) private var topics: [TopicRecord]
    @State private var selectedTopicID: UUID?
    @State private var selectedAttemptID: UUID?
    @State private var searchText = ""

    private var visibleAttempts: [AnswerAttemptRecord] {
        attempts.filter { attempt in
            guard attempt.question.trashedAt == nil else { return false }
            guard selectedTopicID == nil || attempt.question.topic.id == selectedTopicID else {
                return false
            }
            return HistoryQuery.matches(attempt, query: searchText)
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
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("还没有回答历史", systemImage: "clock.arrow.circlepath")
                    } else {
                        ContentUnavailableView("没有匹配的回答", systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(visibleAttempts, id: \.id) { attempt in
                        Button {
                            selectedAttemptID = attempt.id
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
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(HistoryAccessibilityID.row).\(attempt.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle("历史")
        .searchable(text: $searchText, prompt: "搜索题目、回答或 Topic")
        .sheet(isPresented: detailSheetBinding) {
            if let selectedAttemptID,
               let attempt = attempts.first(where: { $0.id == selectedAttemptID }) {
                NavigationStack {
                    AttemptDetailView(attempt: attempt)
                }
            } else {
                ContentUnavailableView("回答记录不存在", systemImage: "clock.badge.questionmark")
            }
        }
        .accessibilityIdentifier(HistoryAccessibilityID.search)
        .accessibilityIdentifier(HistoryAccessibilityID.screen)
    }

    private var detailSheetBinding: Binding<Bool> {
        Binding(
            get: { selectedAttemptID != nil },
            set: { isPresented in
                if !isPresented { selectedAttemptID = nil }
            }
        )
    }

    private func statusText(_ status: AttemptProcessingStatus) -> String {
        switch status {
        case .saved: "待处理"
        case .scoring: "正在获取分数"
        case .feedback: "正在生成评语"
        case .referenceAnswer: "正在生成满分答案"
        case .polishing: "评分中"
        case .evaluating: "评分中"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }
}
