import SwiftData
import SwiftUI

struct QuestionDetailView: View {
    let question: QuestionCardRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showTrashConfirmation = false
    @State private var errorMessage: String?

    private var latestReferenceAnswer: ReferenceAnswerVersionRecord? {
        question.referenceAnswers.max {
            if $0.version == $1.version {
                return $0.createdAt < $1.createdAt
            }
            return $0.version < $1.version
        }
    }

    private var orderedAttempts: [AnswerAttemptRecord] {
        question.attempts.sorted {
            if $0.submittedAt == $1.submittedAt {
                return $0.id.uuidString > $1.id.uuidString
            }
            return $0.submittedAt > $1.submittedAt
        }
    }

    var body: some View {
        List {
            Section("题目") {
                Text(question.questionText)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("library.question.detail.prompt")
            }

            Section("满分答案") {
                if let latestReferenceAnswer {
                    Text(latestReferenceAnswer.answerText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("library.question.detail.reference-answer")
                } else {
                    Text("暂未生成满分答案")
                        .foregroundStyle(.secondary)
                }
            }

            Section("来源") {
                LabeledContent("文件", value: question.sourceDocument.fileName)
                LabeledContent("位置", value: question.sourceAnchor)
            }

            Section("回答历史（\(orderedAttempts.count)）") {
                if orderedAttempts.isEmpty {
                    Text("还没有回答记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedAttempts, id: \.id) { attempt in
                        NavigationLink {
                            AttemptDetailView(attempt: attempt)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attempt.rawText)
                                    .lineLimit(3)
                                HStack {
                                    Text(attempt.submittedAt, format: .dateTime)
                                    if let score = attempt.evaluations.max(by: { $0.createdAt < $1.createdAt })?.totalScore {
                                        Text("· \(score) 分")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("library.question.attempt.\(attempt.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle("题目详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("移到回收站", role: .destructive) {
                    showTrashConfirmation = true
                }
                .accessibilityIdentifier("library.question.move-to-trash")
            }
        }
        .confirmationDialog(
            "移到回收站？",
            isPresented: $showTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("移到回收站", role: .destructive) {
                do {
                    try TrashService().moveToTrash(cardID: question.id, context: modelContext)
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("题目、满分答案和回答历史会保留在回收站，可随时恢复。")
        }
        .alert("无法完成操作", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .accessibilityIdentifier("library.question.detail")
    }
}
