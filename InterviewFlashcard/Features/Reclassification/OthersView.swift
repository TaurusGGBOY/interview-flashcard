import SwiftData
import SwiftUI

enum OthersAccessibilityID {
    static let screen = "reclassification.others.screen"
    static let count = "reclassification.others.count"
    static let runButton = "reclassification.others.run"
    static let progress = "reclassification.others.progress"
    static let summary = "reclassification.others.summary"
}

struct OthersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query private var topics: [TopicRecord]
    @Query private var cards: [QuestionCardRecord]

    @State private var isRunning = false
    @State private var progress: ReclassificationService.Progress?
    @State private var summary: ReclassificationService.Summary?
    @State private var errorMessage: String?

    private var userTopics: [TopicRecord] {
        topics.filter { $0.systemKind != .others }
    }

    private var activeOthersCount: Int {
        cards.filter { !$0.isTrashed && $0.topic.systemKind == .others }.count
    }

    var body: some View {
        List {
            Section {
                LabeledContent("待分类题目", value: "\(activeOthersCount) 道")
                    .accessibilityIdentifier(OthersAccessibilityID.count)

                Button {
                    runReclassification()
                } label: {
                    Label("AI 重新分类", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || userTopics.isEmpty || activeOthersCount == 0)
                .accessibilityIdentifier(OthersAccessibilityID.runButton)
            } footer: {
                Text(footerText)
            }

            if let progress, isRunning {
                Section("处理进度") {
                    ProgressView(
                        value: Double(progress.completedBatches),
                        total: Double(max(progress.totalBatches, 1))
                    )
                    Text("已处理 \(progress.completedBatches)/\(progress.totalBatches) 批")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(OthersAccessibilityID.progress)
            }

            if let summary, !isRunning {
                Section("本次结果") {
                    Text(
                        "已完成：成功 \(summary.succeededBatches) 批，跳过 \(summary.failedBatches) 批，待分类 \(summary.remainingOthersCards) 题"
                    )
                }
                .accessibilityIdentifier(OthersAccessibilityID.summary)
            }
        }
        .navigationTitle("待分类（Others）")
        .accessibilityIdentifier(OthersAccessibilityID.screen)
        .alert(
            "重新分类未能启动",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var footerText: String {
        if userTopics.isEmpty {
            return "请先创建至少一个 Topic，再让 AI 处理全部待分类题目。"
        }
        if activeOthersCount == 0 {
            return "当前没有需要重新分类的题目。"
        }
        return "每批最多处理 50 题；失败批次会跳过，其他批次继续。"
    }

    private func runReclassification() {
        isRunning = true
        progress = nil
        summary = nil
        errorMessage = nil

        Task { @MainActor in
            let service = ReclassificationService(
                aiClient: environment.dependencies.aiClient,
                diagnostics: DiagnosticStateExporter(
                    isEnabled: environment.launchOptions.diagnosticsEnabled
                ),
                now: environment.dependencies.now
            )
            let result = await service.runAllOthers(context: modelContext) { newProgress in
                progress = newProgress
            }
            isRunning = false
            if let fatalErrorMessage = result.fatalErrorMessage {
                errorMessage = fatalErrorMessage
            } else {
                summary = result
            }
        }
    }
}
