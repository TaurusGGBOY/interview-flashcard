import Foundation
import SwiftData
import SwiftUI

@MainActor
struct HistoryQuery {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func global(topicID: UUID? = nil, questionID: UUID? = nil) throws -> [AnswerAttemptRecord] {
        let attempts = try context.fetch(FetchDescriptor<AnswerAttemptRecord>())
        return attempts
            .filter { attempt in
                guard attempt.question.trashedAt == nil else { return false }
                if let topicID, attempt.question.topic.id != topicID { return false }
                if let questionID, attempt.question.id != questionID { return false }
                return true
            }
            .sorted(by: Self.newestFirst)
    }

    func forQuestion(_ question: QuestionCardRecord) throws -> [AnswerAttemptRecord] {
        try global(questionID: question.id)
    }

    static func newestFirst(_ lhs: AnswerAttemptRecord, _ rhs: AnswerAttemptRecord) -> Bool {
        if lhs.submittedAt == rhs.submittedAt {
            return lhs.id.uuidString > rhs.id.uuidString
        }
        return lhs.submittedAt > rhs.submittedAt
    }
}

struct AttemptDetailView: View {
    let attempt: AnswerAttemptRecord

    private var latestPolish: PolishResultRecord? {
        attempt.polishResults.max {
            if $0.revision == $1.revision { return $0.createdAt < $1.createdAt }
            return $0.revision < $1.revision
        }
    }

    private var latestEvaluation: EvaluationRecord? {
        attempt.evaluations.max { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            Section("题目快照") {
                Text(attempt.questionTextSnapshot)
                LabeledContent("满分答案版本", value: "v\(attempt.referenceAnswerVersion)")
                Text(attempt.referenceAnswerTextSnapshot)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("回答") {
                LabeledContent("输入方式", value: attempt.inputMode == .voice ? "语音" : "文字")
                LabeledContent("提交时间", value: attempt.submittedAt.formatted(date: .abbreviated, time: .shortened))
                Text(attempt.rawText)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("history.attempt.raw")
            }

            if let audioAsset = attempt.audioAsset {
                Section("本地录音") {
                    LabeledContent("时长", value: "\(audioAsset.duration, specifier: "%.1f") 秒")
                    LocalAudioPlaybackButton(audioAsset: audioAsset)
                }
            }

            Section("润色版本") {
                if let latestPolish {
                    LabeledContent("修订", value: "v\(latestPolish.revision)")
                    Text(latestPolish.polishedText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("history.attempt.polished")
                } else {
                    Text("尚未完成润色（\(statusText(for: attempt.processingStatus))）")
                        .foregroundStyle(.secondary)
                }
            }

            Section("AI 评分") {
                if let latestEvaluation {
                    if let total = latestEvaluation.totalScore {
                        LabeledContent("总分", value: "\(total) / 100")
                            .accessibilityIdentifier("history.attempt.total-score")
                    } else {
                        Text("本次回答不可评分")
                    }
                    ForEach(ScoreDimension.allCases, id: \.self) { dimension in
                        LabeledContent(dimension.displayName, value: "\(latestEvaluation.dimensionScores[dimension])")
                    }
                    Text("模型：\(latestEvaluation.modelID) · 提示词：\(latestEvaluation.promptVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("等待评分")
                        .foregroundStyle(.secondary)
                }
            }

            if let failure = attempt.failureSummary {
                Section("处理状态") {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("回答详情")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("history.attempt.detail")
    }

    private func statusText(for status: AttemptProcessingStatus) -> String {
        switch status {
        case .saved: "待处理"
        case .polishing: "润色中"
        case .evaluating: "评分中"
        case .completed: "已完成"
        case .failed: "失败"
        }
    }
}

struct QuestionHistoryView: View {
    let question: QuestionCardRecord
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(attempts, id: \.id) { attempt in
                NavigationLink {
                    AttemptDetailView(attempt: attempt)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attempt.submittedAt, format: .dateTime)
                        Text(attempt.rawText)
                            .lineLimit(2)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if attempts.isEmpty {
                ContentUnavailableView("还没有回答历史", systemImage: "clock")
            }
        }
        .navigationTitle("回答历史")
    }

    private var attempts: [AnswerAttemptRecord] {
        (try? HistoryQuery(context: context).forQuestion(question)) ?? []
    }
}

private struct LocalAudioPlaybackButton: View {
    let audioAsset: AudioAssetRecord
    @State private var isPlaying = false

    var body: some View {
        let fileURL = Self.audioURL(for: audioAsset.relativePath)
        Button {
            // Playback is intentionally local-only. A later audio player can replace
            // this state toggle without changing the persisted contract.
            isPlaying.toggle()
        } label: {
            Label(isPlaying ? "暂停录音" : "播放录音", systemImage: isPlaying ? "pause.fill" : "play.fill")
        }
        .disabled(!FileManager.default.fileExists(atPath: fileURL.path))
        .accessibilityIdentifier("history.audio.playback")
    }

    private static func audioURL(for relativePath: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InterviewFlashcard", isDirectory: true)
            .appendingPathComponent(relativePath)
    }
}
