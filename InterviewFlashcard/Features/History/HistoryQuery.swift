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

    nonisolated static func matches(_ attempt: AnswerAttemptRecord, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }

        return [
            attempt.questionTextSnapshot,
            attempt.rawText,
            attempt.question.topic.name
        ].contains { value in
            value.range(
                of: normalizedQuery,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) != nil
        }
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
    @Environment(\.dismiss) private var dismiss

    private var latestPolish: PolishResultRecord? {
        attempt.polishResults.max {
            if $0.revision == $1.revision { return $0.createdAt < $1.createdAt }
            return $0.revision < $1.revision
        }
    }

    private var latestEvaluation: EvaluationRecord? {
        attempt.evaluations.max { $0.createdAt < $1.createdAt }
    }

    @ViewBuilder
    var body: some View {
        if let latestEvaluation {
            // A historical scored answer is the same product state as the
            // result shown immediately after scoring. Reuse that complete
            // presentation so the radar chart, evidence, gaps, and answer
            // comparison cannot drift apart between the two entry points.
            EvaluationResultView(
                evaluation: latestEvaluation,
                onContinue: { dismiss() },
                onClose: { dismiss() },
                continueTitle: "关闭",
                continueSystemImage: "xmark"
            )
            .accessibilityIdentifier("history.attempt.detail")
        } else {
            pendingAttemptView
        }
    }

    private var pendingAttemptView: some View {
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
                    LabeledContent("时长", value: String(format: "%.1f 秒", audioAsset.duration))
                    LocalAudioPlaybackButton(audioAsset: audioAsset)
                }
            }

            if let latestPolish {
                Section("历史润色版本") {
                    LabeledContent("修订", value: "v\(latestPolish.revision)")
                    Text(latestPolish.polishedText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("history.attempt.polished")
                }
            }

            Section("AI 评分") {
                Text("等待评分")
                    .foregroundStyle(.secondary)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
                .accessibilityIdentifier("history.attempt.close")
            }
        }
        .accessibilityIdentifier("history.attempt.detail")
    }

}

struct QuestionHistoryView: View {
    let question: QuestionCardRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selectedAttemptID: UUID?

    var body: some View {
        List {
            ForEach(attempts, id: \.id) { attempt in
                Button {
                    selectedAttemptID = attempt.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attempt.submittedAt, format: .dateTime)
                        Text(attempt.rawText)
                            .lineLimit(2)
                            .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if attempts.isEmpty {
                ContentUnavailableView("还没有回答历史", systemImage: "clock")
            }
        }
        .navigationTitle("回答历史")
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
                .accessibilityIdentifier("history.question.close")
            }
        }
    }

    private var attempts: [AnswerAttemptRecord] {
        (try? HistoryQuery(context: context).forQuestion(question)) ?? []
    }

    private var detailSheetBinding: Binding<Bool> {
        Binding(
            get: { selectedAttemptID != nil },
            set: { isPresented in
                if !isPresented { selectedAttemptID = nil }
            }
        )
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
