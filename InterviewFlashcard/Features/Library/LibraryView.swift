import SwiftData
import SwiftUI

enum LibraryAccessibilityID {
    static let screen = "library.screen"
    static let createTopic = "library.topic.create"
    static let topicEditor = "library.topic.editor"
    static let topicNameField = "library.topic.editor.name"
    static let topicEditorSave = "library.topic.editor.save"
    static let topicEditorCancel = "library.topic.editor.cancel"
    static let topicValidation = "library.topic.editor.validation"
    static let search = "library.search"
    static let importMarkdown = "library.import-markdown"
    static let addQuestion = "library.question.add"
    static let manualQuestionField = "library.question.editor.question"
    static let manualAnswerField = "library.question.editor.reference-answer"
    static let manualTopicPicker = "library.question.editor.topic"
    static let manualQuestionSave = "library.question.editor.save"
    static let manualQuestionCancel = "library.question.editor.cancel"
    static let questionSelectAll = "library.question.select-all"
    static let questionBatchMove = "library.question.batch-move"
    static let topicExpanded = "library.topic.expanded"
    static let questionDetail = "library.question.detail.sheet"
    static let questionMovePicker = "library.question.move.picker"
    static let questionMoveConfirm = "library.question.move.confirm"

    static func topicRow(_ topic: TopicRecord) -> String {
        topic.systemKind == .others ? "library.topic.others" : "library.topic.\(topic.id.uuidString)"
    }

    static func topicActions(_ topic: TopicRecord) -> String {
        "library.topic.actions.\(topic.id.uuidString)"
    }

    static func questionRow(_ question: QuestionCardRecord) -> String {
        "library.question.\(question.id.uuidString)"
    }

    static func questionSelection(_ question: QuestionCardRecord) -> String {
        "library.question.selection.\(question.id.uuidString)"
    }

    static func startAnswer(_ question: QuestionCardRecord) -> String {
        "library.question.start-answer.\(question.id.uuidString)"
    }

    static func moveDestination(_ topic: TopicRecord) -> String {
        "library.question.move.destination.\(topic.id.uuidString)"
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var topics: [TopicRecord]

    private let service: TopicService
    @State private var isCreatingTopic = false
    @State private var isShowingImport = false
    @State private var isShowingManualQuestion = false
    @State private var isShowingTrash = false
    @State private var isSelectingQuestions = false
    @State private var selectedQuestionIDs: Set<UUID> = []
    @State private var isChoosingQuestionDestination = false
    @State private var selectedMoveDestinationID: UUID?
    @State private var topicToRename: TopicRecord?
    @State private var isRenamingTopic = false
    @State private var pendingTopicDeletionID: UUID?
    @State private var pendingTopicDeletionImpact: TopicService.TopicDeletionImpact?
    @State private var isConfirmingPermanentTopicDeletion = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var expandedTopicIDs: Set<UUID> = []

    private let onOpenQuestion: (UUID) -> Void

    init(
        service: TopicService = TopicService(),
        onOpenQuestion: @escaping (UUID) -> Void = { _ in }
    ) {
        self.service = service
        self.onOpenQuestion = onOpenQuestion
    }

    private var orderedTopics: [TopicRecord] {
        topics.sorted(by: TopicService.libraryOrder)
    }

    private var searchResults: [QuestionCardRecord] {
        LibrarySearch.results(
            from: topics.flatMap(\.cards),
            query: searchText
        )
    }

    private var selectableQuestions: [QuestionCardRecord] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return topics
                .flatMap(\.cards)
                .filter { !$0.isTrashed }
        }
        return searchResults
    }

    var body: some View {
        List {
            Section("操作") {
                Button {
                    exitQuestionSelection()
                    isShowingImport = true
                } label: {
                    Label("导入文本文件", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier(LibraryAccessibilityID.importMarkdown)

                Button {
                    exitQuestionSelection()
                    isShowingManualQuestion = true
                } label: {
                    Label("手动添加题目", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier(LibraryAccessibilityID.addQuestion)
            }

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    if orderedTopics.isEmpty {
                        ContentUnavailableView(
                            "题库尚未准备好",
                            systemImage: "books.vertical",
                            description: Text("导入文本文件或手动添加题目后，题目会显示在这里。")
                        )
                    } else {
                        ForEach(orderedTopics, id: \.id) { topic in
                            topicRow(topic)
                        }
                    }
                } header: {
                    topicsSectionHeader
                }
            } else {
                Section("搜索结果（\(searchResults.count)）") {
                    if searchResults.isEmpty {
                        ContentUnavailableView("没有匹配的题目", systemImage: "magnifyingglass")
                    } else {
                        ForEach(searchResults, id: \.id) { question in
                            searchableQuestionRow(question)
                        }
                    }
                }
            }
        }
        .navigationTitle("题库")
        .searchable(text: $searchText, prompt: "搜索题目或 Topic")
        .accessibilityIdentifier(LibraryAccessibilityID.search)
        .onChange(of: searchText) { _, _ in
            exitQuestionSelection()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exitQuestionSelection()
                    isShowingTrash = true
                } label: {
                    Label("回收站", systemImage: "trash")
                }
                .accessibilityIdentifier("library.trash")
            }
        }
        .sheet(isPresented: $isShowingImport) {
            NavigationStack {
                ImportView()
            }
        }
        .sheet(isPresented: $isShowingManualQuestion) {
            NavigationStack {
                ManualQuestionEditorView()
            }
        }
        .sheet(isPresented: $isShowingTrash) {
            NavigationStack {
                TrashView()
            }
        }
        .sheet(isPresented: $isCreatingTopic) {
            TopicEditorView(mode: .create, service: service)
        }
        .sheet(isPresented: $isRenamingTopic, onDismiss: { topicToRename = nil }) {
            if let topicToRename {
                TopicEditorView(mode: .rename(topicToRename), service: service)
            }
        }
        .confirmationDialog(
            permanentDeletionTitle,
            isPresented: $isConfirmingPermanentTopicDeletion,
            titleVisibility: .visible
        ) {
            Button("删除 Topic 和全部题目", role: .destructive) {
                permanentlyDeletePendingTopic()
            }
            Button("取消", role: .cancel) {
                clearPendingTopicDeletion()
            }
        } message: {
            Text(permanentDeletionMessage)
        }
        .sheet(isPresented: $isChoosingQuestionDestination, onDismiss: {
            selectedMoveDestinationID = nil
        }) {
            QuestionBatchMoveView(
                topics: orderedTopics,
                selectedCount: selectedQuestionIDs.count,
                selectedTopicID: $selectedMoveDestinationID,
                onConfirm: moveSelectedQuestions(to:)
            )
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .accessibilityIdentifier(LibraryAccessibilityID.screen)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectingQuestions {
                HStack(spacing: 12) {
                    Button(action: toggleSelectAllQuestions) {
                        Label(allSelectableQuestionsSelected ? "取消全选" : "全选", systemImage: allSelectableQuestionsSelected ? "checkmark.circle.fill" : "checklist")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectableQuestions.isEmpty)
                    .accessibilityIdentifier(LibraryAccessibilityID.questionSelectAll)

                    Button(action: prepareToMoveSelectedQuestions) {
                        Label("更改 Topic（\(selectedQuestionIDs.count)）", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedQuestionIDs.isEmpty)
                    .accessibilityIdentifier(LibraryAccessibilityID.questionBatchMove)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private var topicsSectionHeader: some View {
        HStack(spacing: 8) {
            Text("Topics")
            Button {
                exitQuestionSelection()
                isCreatingTopic = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建 Topic")
            .accessibilityIdentifier(LibraryAccessibilityID.createTopic)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            exitQuestionSelection()
        }
    }

    @ViewBuilder
    private func topicRow(_ topic: TopicRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    exitQuestionSelection()
                    toggleTopicExpansion(topic)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName(for: topic))
                                .font(.body.weight(topic.systemKind == .others ? .semibold : .regular))
                            Text("\(activeCardCount(for: topic)) 道题")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: expandedTopicIDs.contains(topic.id) ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(LibraryAccessibilityID.topicRow(topic))
                .accessibilityAddTraits(.isButton)

                if topic.systemKindRaw == nil {
                    Menu {
                        Button("重命名") {
                            exitQuestionSelection()
                            topicToRename = topic
                            isRenamingTopic = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("管理 \(topic.name)")
                    .accessibilityIdentifier(LibraryAccessibilityID.topicActions(topic))
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }

            if expandedTopicIDs.contains(topic.id) {
                topicQuestions(topic)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if topic.systemKind != .others {
                Button(role: .destructive) {
                    prepareToPermanentlyDelete(topic)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func searchableQuestionRow(_ question: QuestionCardRecord) -> some View {
        Button {
            handleQuestionTap(question)
        } label: {
            HStack(spacing: 12) {
                if isSelectingQuestions {
                    questionSelectionIndicator(for: question)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        questionNumberText(for: question)
                        Text(question.questionText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(displayName(for: question.topic))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                answeredIndicator(for: question)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            isSelectingQuestions
                ? LibraryAccessibilityID.questionSelection(question)
                : LibraryAccessibilityID.questionRow(question)
        )
        .accessibilityLabel(
            isSelectingQuestions
                ? questionSelectionLabel(for: question)
                : questionBrowsingLabel(for: question)
        )
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in beginQuestionSelection(with: question) }
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func topicQuestions(_ topic: TopicRecord) -> some View {
        let activeCards = topic.cards
            .filter { !$0.isTrashed }
            .sorted(by: LibraryQuestionOrdering.newestFirst)

        if activeCards.isEmpty {
            Text("暂无题目")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    exitQuestionSelection()
                }
        } else {
            ForEach(activeCards, id: \.id) { question in
                Button {
                    handleQuestionTap(question)
                } label: {
                    HStack(spacing: 12) {
                        if isSelectingQuestions {
                            questionSelectionIndicator(for: question)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            questionNumberText(for: question)
                            Text(question.questionText)
                                .multilineTextAlignment(.leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        answeredIndicator(for: question)
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(
                    isSelectingQuestions
                        ? LibraryAccessibilityID.questionSelection(question)
                        : LibraryAccessibilityID.questionRow(question)
                )
                .accessibilityLabel(
                    isSelectingQuestions
                        ? questionSelectionLabel(for: question)
                        : questionBrowsingLabel(for: question)
                )
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in beginQuestionSelection(with: question) }
                )
            }
        }
    }

    @ViewBuilder
    private func questionNumberText(for question: QuestionCardRecord) -> some View {
        if let questionNumber = question.questionNumber {
            Text("\(questionNumber)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func answeredIndicator(for question: QuestionCardRecord) -> some View {
        if question.hasBeenAnswered && !isSelectingQuestions {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.medium)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private func questionBrowsingLabel(for question: QuestionCardRecord) -> String {
        question.hasBeenAnswered ? "\(question.questionText)，已回答" : question.questionText
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }

    private var allSelectableQuestionsSelected: Bool {
        !selectableQuestions.isEmpty
            && selectableQuestions.allSatisfy { selectedQuestionIDs.contains($0.id) }
    }

    private func activeCardCount(for topic: TopicRecord) -> Int {
        topic.cards.lazy.filter { !$0.isTrashed }.count
    }

    private var permanentDeletionTitle: String {
        guard let topic = pendingTopicDeletion else { return "删除 Topic" }
        return "删除“\(displayName(for: topic))”？"
    }

    private var permanentDeletionMessage: String {
        guard let impact = pendingTopicDeletionImpact else {
            return "该操作不可撤销。"
        }
        return "将永久删除这个 Topic 及其中 \(impact.questionCount) 道题，相关回答和评分记录也会一并删除。该操作不可撤销。"
    }

    private var pendingTopicDeletion: TopicRecord? {
        guard let pendingTopicDeletionID else { return nil }
        return orderedTopics.first { $0.id == pendingTopicDeletionID }
    }

    private func prepareToPermanentlyDelete(_ topic: TopicRecord) {
        exitQuestionSelection()
        guard topic.systemKind != .others else { return }
        do {
            pendingTopicDeletionImpact = try service.deletionImpact(
                for: topic,
                context: modelContext
            )
            pendingTopicDeletionID = topic.id
            isConfirmingPermanentTopicDeletion = true
        } catch {
            clearPendingTopicDeletion()
            errorMessage = error.localizedDescription
        }
    }

    private func permanentlyDeletePendingTopic() {
        guard let topic = pendingTopicDeletion else {
            clearPendingTopicDeletion()
            return
        }
        do {
            try service.permanentlyDelete(topic: topic, context: modelContext)
            expandedTopicIDs.remove(topic.id)
            clearPendingTopicDeletion()
        } catch {
            errorMessage = error.localizedDescription
            clearPendingTopicDeletion()
        }
    }

    private func clearPendingTopicDeletion() {
        pendingTopicDeletionID = nil
        pendingTopicDeletionImpact = nil
        isConfirmingPermanentTopicDeletion = false
    }

    private func toggleTopicExpansion(_ topic: TopicRecord) {
        if expandedTopicIDs.contains(topic.id) {
            expandedTopicIDs.remove(topic.id)
        } else {
            expandedTopicIDs.insert(topic.id)
        }
    }

    private func handleQuestionTap(_ question: QuestionCardRecord) {
        if isSelectingQuestions {
            toggleQuestionSelection(question)
        } else {
            onOpenQuestion(question.id)
        }
    }

    private func beginQuestionSelection(with question: QuestionCardRecord) {
        guard !question.isTrashed else { return }
        if !isSelectingQuestions {
            isSelectingQuestions = true
            expandedTopicIDs.formUnion(orderedTopics.map(\.id))
        }
        selectedQuestionIDs.insert(question.id)
    }

    private func exitQuestionSelection() {
        guard isSelectingQuestions else { return }
        isSelectingQuestions = false
        selectedQuestionIDs.removeAll()
    }

    private func toggleQuestionSelection(_ question: QuestionCardRecord) {
        guard !question.isTrashed else { return }
        if selectedQuestionIDs.contains(question.id) {
            selectedQuestionIDs.remove(question.id)
        } else {
            selectedQuestionIDs.insert(question.id)
        }
    }

    private func toggleSelectAllQuestions() {
        let candidateIDs = Set(selectableQuestions.map(\.id))
        guard !candidateIDs.isEmpty else { return }
        if candidateIDs.isSubset(of: selectedQuestionIDs) {
            selectedQuestionIDs.subtract(candidateIDs)
        } else {
            selectedQuestionIDs.formUnion(candidateIDs)
        }
    }

    private func prepareToMoveSelectedQuestions() {
        guard !selectedQuestionIDs.isEmpty else { return }
        selectedMoveDestinationID = nil
        isChoosingQuestionDestination = true
    }

    private func moveSelectedQuestions(to destination: TopicRecord) {
        let cards = topics
            .flatMap(\.cards)
            .filter { selectedQuestionIDs.contains($0.id) && !$0.isTrashed }

        do {
            try service.moveCards(cards, to: destination, context: modelContext)
            selectedQuestionIDs.removeAll()
            isSelectingQuestions = false
            isChoosingQuestionDestination = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func questionSelectionIndicator(for question: QuestionCardRecord) -> some View {
        Image(systemName: selectedQuestionIDs.contains(question.id) ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selectedQuestionIDs.contains(question.id) ? Color.accentColor : Color.secondary)
            .imageScale(.large)
            .accessibilityHidden(true)
    }

    private func questionSelectionLabel(for question: QuestionCardRecord) -> String {
        let action = selectedQuestionIDs.contains(question.id) ? "取消选择" : "选择"
        return "\(action)题目：\(question.questionText)"
    }

}

private struct QuestionBatchMoveView: View {
    @Environment(\.dismiss) private var dismiss

    let topics: [TopicRecord]
    let selectedCount: Int
    @Binding var selectedTopicID: UUID?
    let onConfirm: (TopicRecord) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("移动到 Topic", selection: $selectedTopicID) {
                        Text("请选择 Topic")
                            .tag(Optional<UUID>.none)
                        ForEach(topics, id: \.id) { topic in
                            Text(displayName(for: topic))
                                .tag(Optional(topic.id))
                        }
                    }
                    .accessibilityIdentifier(LibraryAccessibilityID.questionMovePicker)
                } header: {
                    Text("已选择 \(selectedCount) 道题")
                } footer: {
                    Text("选择目标 Topic 后，点击右上角“确定”完成批量移动。")
                }
            }
            .navigationTitle("移动题目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        guard let selectedTopicID,
                              let destination = topics.first(where: { $0.id == selectedTopicID })
                        else { return }
                        onConfirm(destination)
                        dismiss()
                    }
                    .disabled(selectedTopicID == nil)
                    .accessibilityIdentifier(LibraryAccessibilityID.questionMoveConfirm)
                }
            }
        }
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }
}

private struct ManualQuestionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var topics: [TopicRecord]

    @State private var selectedTopicID: UUID?
    @State private var questionText = ""
    @State private var referenceAnswer = ""
    @State private var validationMessage: String?

    private var orderedTopics: [TopicRecord] {
        topics.sorted(by: TopicService.libraryOrder)
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $questionText)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier(LibraryAccessibilityID.manualQuestionField)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("题目")
            } footer: {
                Text("保存后可以直接从题目详情开始回答。")
            }

            Section("归类") {
                if orderedTopics.isEmpty {
                    Text("暂无可用 Topic，请先创建一个 Topic。")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Topic", selection: $selectedTopicID) {
                        ForEach(orderedTopics, id: \.id) { topic in
                            Text(displayName(for: topic))
                                .tag(Optional(topic.id))
                        }
                    }
                    .accessibilityIdentifier(LibraryAccessibilityID.manualTopicPicker)
                }
            }

            Section {
                TextEditor(text: $referenceAnswer)
                    .frame(minHeight: 140)
                    .accessibilityIdentifier(LibraryAccessibilityID.manualAnswerField)
            } header: {
                Text("满分答案（可选）")
            } footer: {
                Text("可以先只添加题目，之后仍可从详情页查看并开始回答。")
            }
        }
        .navigationTitle("手动添加题目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .accessibilityIdentifier(LibraryAccessibilityID.manualQuestionCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(orderedTopics.isEmpty)
                    .accessibilityIdentifier(LibraryAccessibilityID.manualQuestionSave)
            }
        }
        .onAppear {
            if selectedTopicID == nil {
                selectedTopicID = orderedTopics.first?.id
            }
        }
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }

    private func save() {
        validationMessage = nil
        let trimmedQuestion = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            validationMessage = "请输入题目内容。"
            return
        }
        guard let selectedTopicID,
              let topic = topics.first(where: { $0.id == selectedTopicID }) else {
            validationMessage = "请选择一个 Topic。"
            return
        }

        do {
            let timestamp = Date()
            let questionNumber = try QuestionNumberingService().nextNumber(context: modelContext)
            let source = SourceDocumentRecord(
                fileName: "手动添加",
                contentHash: "manual-\(UUID().uuidString)",
                importerVersion: "manual-v1",
                importedAt: timestamp
            )
            let card = QuestionCardRecord(
                questionNumber: questionNumber,
                questionText: trimmedQuestion,
                sourceAnchor: "手动添加",
                createdAt: timestamp,
                updatedAt: timestamp,
                activatedAt: timestamp,
                topic: topic,
                sourceDocument: source
            )

            modelContext.insert(source)
            modelContext.insert(card)

            let trimmedAnswer = referenceAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAnswer.isEmpty {
                modelContext.insert(
                    ReferenceAnswerVersionRecord(
                        version: 1,
                        answerText: trimmedAnswer,
                        origin: .userEdited,
                        createdAt: timestamp,
                        question: card
                    )
                )
            }

            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
