import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \ImportRunRecord.createdAt, order: .reverse) private var runs: [ImportRunRecord]

    @State private var isShowingFileImporter = false
    @State private var isWorking = false
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
                Text("AI 会自动拆题、整理并按已有 Topic 分类，不需要逐题审核。")
            }

            if runs.isEmpty {
                ContentUnavailableView(
                    "还没有导入记录",
                    systemImage: "doc.text",
                    description: Text("从 Files 选择一个或多个 .md 文件。")
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
        .overlay {
            if isWorking {
                ProgressView("正在处理题库…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier(ImportAccessibilityID.workingIndicator)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
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
            let completedBatches = run.refinementBatches.filter { $0.status == .completed }.count
            Text("拆题 \(completedChunks)/\(run.chunks.count) · 整理 \(completedBatches)/\(run.refinementBatches.count) · 题目 \(run.sourceDocument.cards.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if run.status == .failed {
                Button("继续处理") {
                    continueRun(run.id)
                }
                .disabled(isWorking)
                .accessibilityIdentifier(ImportAccessibilityID.continueButton(run.id))
            } else if run.status == .active {
                NavigationLink("查看生成题目") {
                    ImportedCardsView(sourceDocument: run.sourceDocument)
                }
                .accessibilityIdentifier(ImportAccessibilityID.generatedCardsLink(run.id))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ImportAccessibilityID.runRow(run.id))
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
                try await makeCoordinator().continueRun(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func makeCoordinator() -> ImportCoordinator {
        ImportCoordinator(
            context: modelContext,
            aiClient: environment.dependencies.aiClient,
            diagnostics: DiagnosticStateExporter(
                isEnabled: environment.launchOptions.diagnosticsEnabled
            ),
            now: environment.dependencies.now
        )
    }

    private func stageTitle(_ status: ImportRunStatus) -> String {
        switch status {
        case .queued: "等待处理"
        case .chunking: "正在分片"
        case .decomposing: "正在拆题"
        case .refining: "正在整理"
        case .activating: "正在激活"
        case .active: "已完成"
        case .failed: "失败"
        }
    }
}

private struct ImportedCardsView: View {
    let sourceDocument: SourceDocumentRecord

    var body: some View {
        List(sourceDocument.cards.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { card in
            NavigationLink {
                QuestionDetailView(question: card)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.questionText)
                    Text(card.topic.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(sourceDocument.fileName)
    }
}

private enum ImportAccessibilityID {
    static let importButton = "import.markdown.button"
    static let workingIndicator = "import.working"

    static func runRow(_ id: UUID) -> String { "import.run.\(id.uuidString)" }
    static func continueButton(_ id: UUID) -> String { "import.continue.\(id.uuidString)" }
    static func generatedCardsLink(_ id: UUID) -> String { "import.cards.\(id.uuidString)" }
}
