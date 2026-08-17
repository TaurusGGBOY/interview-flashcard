import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \ImportRunRecord.createdAt, order: .reverse) private var runs: [ImportRunRecord]

    @State private var isShowingFileImporter = false
    @State private var isWorking = false
    @State private var selectedReviewRunID: UUID?
    @State private var selectedGeneratedSourceID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("导入 Markdown", systemImage: "square.and.arrow.down")
                }
                .disabled(isWorking)
                .accessibilityIdentifier(ImportAccessibilityID.importButton)
            } footer: {
                Text("选择 Markdown 后只在后台提取题目；完成后一次性导入全部题目，首次答题时再生成满分答案。")
            }

            if runs.isEmpty {
                ContentUnavailableView(
                    "还没有导入记录",
                    systemImage: "doc.text",
                    description: Text("从 Files 选择 Markdown（.md）文件。")
                )
            } else {
                Section("导入记录") {
                    ForEach(runs, id: \.id) { run in
                        runRow(run)
                    }
                }
            }
        }
        .navigationTitle("Markdown 导入")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
                .accessibilityIdentifier(ImportAccessibilityID.close)
            }
        }
        .overlay {
            if isWorking {
                ProgressView("正在创建后台任务…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier(ImportAccessibilityID.workingIndicator)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .text],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                start(urls: urls)
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .sheet(isPresented: reviewSheetBinding) {
            if let selectedReviewRunID,
               let run = runs.first(where: { $0.id == selectedReviewRunID }) {
                NavigationStack {
                    ImportReviewView(run: run)
                }
            } else {
                ContentUnavailableView("导入记录不存在", systemImage: "doc.questionmark")
            }
        }
        .sheet(isPresented: generatedCardsSheetBinding) {
            if let selectedGeneratedSourceID,
               let sourceDocument = runs.lazy.map(\.sourceDocument).first(where: { $0.id == selectedGeneratedSourceID }) {
                NavigationStack {
                    ImportedCardsView(sourceDocument: sourceDocument)
                }
            } else {
                ContentUnavailableView("导入文档不存在", systemImage: "doc.questionmark")
            }
        }
        .accessibilityIdentifier(ImportAccessibilityID.screen)
    }

    @ViewBuilder
    private func runRow(_ run: ImportRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(run.sourceDocument.fileName)
                    .font(.headline)
                Spacer()
                Text(stageTitle(run.status))
                    .foregroundStyle(run.status == .failed ? Color.red : Color.secondary)
            }

            let completedChunks = run.chunks.filter { $0.status == .completed }.count
            let failedChunks = run.chunks.filter { $0.status == .failed }.count
            let unfinishedChunks = run.chunks.count - completedChunks - failedChunks
            let candidateCount = run.chunks
                .flatMap(\.candidates)
                .filter { $0.status.isActivationEligible }
                .count
            let chunkProgress = {
                switch run.status {
                case .chunking, .decomposing, .refining, .activating:
                    "拆题 \(completedChunks)/\(run.chunks.count) · AI处理中 \(unfinishedChunks)"
                case .failed:
                    "拆题 \(completedChunks)/\(run.chunks.count) · 失败 \(failedChunks)"
                default:
                    "拆题 \(completedChunks)/\(run.chunks.count)"
                }
            }()
            Text("\(chunkProgress) · 候选 \(candidateCount) · 已导入 \(run.sourceDocument.cards.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if run.status == .failed,
               let errorSummary = run.errorSummary,
               !errorSummary.isEmpty {
                Text(errorSummary)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if run.status == .failed {
                Button("继续处理") {
                    continueRun(run.id)
                }
                .disabled(isWorking)
                .accessibilityIdentifier(ImportAccessibilityID.continueButton(run.id))
            } else if run.status == .ready {
                Button("查看整理结果") {
                    selectedReviewRunID = run.id
                }
                .accessibilityIdentifier(ImportAccessibilityID.reviewLink(run.id))
            } else if run.status == .active {
                Button("查看生成题目") {
                    selectedGeneratedSourceID = run.sourceDocument.id
                }
                .accessibilityIdentifier(ImportAccessibilityID.generatedCardsLink(run.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ImportAccessibilityID.runRow(run.id))
    }

    private var reviewSheetBinding: Binding<Bool> {
        Binding(
            get: { selectedReviewRunID != nil },
            set: { isPresented in
                if !isPresented { selectedReviewRunID = nil }
            }
        )
    }

    private var generatedCardsSheetBinding: Binding<Bool> {
        Binding(
            get: { selectedGeneratedSourceID != nil },
            set: { isPresented in
                if !isPresented { selectedGeneratedSourceID = nil }
            }
        )
    }

    private func start(urls: [URL]) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await makeCoordinator().start(urls: urls)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func continueRun(_ id: UUID) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try makeCoordinator().enqueueContinuation(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func makeCoordinator() -> ImportCoordinator {
        if let coordinator = environment.importCoordinator {
            return coordinator
        }

        let coordinator = ImportCoordinator(
            context: modelContext,
            aiClient: environment.dependencies.aiClient,
            diagnostics: DiagnosticStateExporter(
                isEnabled: environment.launchOptions.diagnosticsEnabled
            ),
            singlePassLLMImport: false,
            refinementBatchSize: 4,
            now: environment.dependencies.now
        )
        environment.importCoordinator = coordinator
        return coordinator
    }

    private func stageTitle(_ status: ImportRunStatus) -> String {
        switch status {
        case .queued: "等待处理"
        case .chunking: "正在分片"
        case .decomposing: "正在拆题"
        case .refining: "正在整理"
        case .activating: "正在激活"
        case .ready: "待一键导入"
        case .active: "已完成"
        case .failed: "失败"
        }
    }
}

private struct ImportedCardsView: View {
    let sourceDocument: SourceDocumentRecord
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestionID: UUID?

    var body: some View {
        List(sourceDocument.cards.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { card in
            Button {
                selectedQuestionID = card.id
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.questionText)
                    Text(card.topic.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(sourceDocument.fileName)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: questionDetailSheetBinding) {
            if let selectedQuestionID,
               let question = sourceDocument.cards.first(where: { $0.id == selectedQuestionID }) {
                QuestionDetailView(question: question)
            } else {
                ContentUnavailableView("题目不存在", systemImage: "questionmark.folder")
            }
        }
    }

    private var questionDetailSheetBinding: Binding<Bool> {
        Binding(
            get: { selectedQuestionID != nil },
            set: { isPresented in
                if !isPresented { selectedQuestionID = nil }
            }
        )
    }
}

private struct ImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query private var topics: [TopicRecord]

    let run: ImportRunRecord

    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var candidates: [QuestionCandidateRecord] {
        run.chunks
            .flatMap(\.candidates)
            .filter { $0.status.isActivationEligible }
            .sorted { $0.sourceOrder < $1.sourceOrder }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("后台提取已完成", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text("共提取出 \(candidates.count) 道题目。确认后会全部写入题库，不支持逐题选择。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("如果需要修改题目或答案，请在导入后进入对应 Topic 编辑。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        confirmImport()
                    } label: {
                        Label("一键导入全部题目", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming)
                    .accessibilityIdentifier(ImportAccessibilityID.confirmAllButton(run.id))
                }
                .padding(.vertical, 4)
            }

            Section("将导入的题目（\(candidates.count)）") {
                ForEach(candidates, id: \.id) { candidate in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.questionText)
                        Text(topicName(for: candidate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("整理结果")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
        .overlay {
            if isConfirming {
                ProgressView("正在导入题库…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func confirmImport() {
        isConfirming = true
        Task { @MainActor in
            defer { isConfirming = false }
            do {
                try makeCoordinator().confirmImport(id: run.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func topicName(for candidate: QuestionCandidateRecord) -> String {
        if let proposed = candidate.proposedTopicName,
           topics.contains(where: { $0.name == proposed }) {
            return proposed
        }
        return topics.first(where: { $0.systemKind == .others })?.name ?? "Others"
    }

    private func makeCoordinator() -> ImportCoordinator {
        if let coordinator = environment.importCoordinator {
            return coordinator
        }

        let coordinator = ImportCoordinator(
            context: modelContext,
            aiClient: environment.dependencies.aiClient,
            diagnostics: DiagnosticStateExporter(
                isEnabled: environment.launchOptions.diagnosticsEnabled
            ),
            singlePassLLMImport: false,
            refinementBatchSize: 4,
            now: environment.dependencies.now
        )
        environment.importCoordinator = coordinator
        return coordinator
    }
}

private enum ImportAccessibilityID {
    static let screen = "import.screen"
    static let close = "import.close"
    static let importButton = "import.markdown.button"
    static let workingIndicator = "import.working"

    static func runRow(_ id: UUID) -> String { "import.run.\(id.uuidString)" }
    static func continueButton(_ id: UUID) -> String { "import.continue.\(id.uuidString)" }
    static func reviewLink(_ id: UUID) -> String { "import.review.\(id.uuidString)" }
    static func confirmAllButton(_ id: UUID) -> String { "import.confirm-all.\(id.uuidString)" }
    static func generatedCardsLink(_ id: UUID) -> String { "import.cards.\(id.uuidString)" }
}
