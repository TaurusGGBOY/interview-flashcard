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

    static func topicRow(_ topic: TopicRecord) -> String {
        topic.systemKind == .others ? "library.topic.others" : "library.topic.\(topic.id.uuidString)"
    }

    static func topicActions(_ topic: TopicRecord) -> String {
        "library.topic.actions.\(topic.id.uuidString)"
    }

    static func deleteDestination(_ topic: TopicRecord) -> String {
        "library.topic.delete.destination.\(topic.id.uuidString)"
    }

    static func questionRow(_ question: QuestionCardRecord) -> String {
        "library.question.\(question.id.uuidString)"
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var topics: [TopicRecord]

    private let service: TopicService
    @State private var isCreatingTopic = false
    @State private var topicToRename: TopicRecord?
    @State private var isRenamingTopic = false
    @State private var topicToDelete: TopicRecord?
    @State private var deletionDestinations: [TopicRecord] = []
    @State private var isChoosingDeletionDestination = false
    @State private var errorMessage: String?

    init(service: TopicService = TopicService()) {
        self.service = service
    }

    private var orderedTopics: [TopicRecord] {
        topics.sorted(by: TopicService.libraryOrder)
    }

    var body: some View {
        List {
            Section("Topics") {
                ForEach(orderedTopics, id: \.id) { topic in
                    topicRow(topic)
                }
            }
        }
        .overlay {
            if topics.isEmpty {
                ContentUnavailableView(
                    "题库尚未准备好",
                    systemImage: "books.vertical",
                    description: Text("系统正在创建待分类 Topic。")
                )
            }
        }
        .navigationTitle("题库")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingTopic = true
                } label: {
                    Label("新建 Topic", systemImage: "plus")
                }
                .accessibilityIdentifier(LibraryAccessibilityID.createTopic)
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ImportView()
                } label: {
                    Label("导入 Markdown", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("library.import-markdown")
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    TrashView()
                } label: {
                    Label("回收站", systemImage: "trash")
                }
                .accessibilityIdentifier("library.trash")
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
            "删除“\(topicToDelete?.name ?? "")”",
            isPresented: $isChoosingDeletionDestination,
            titleVisibility: .visible
        ) {
            ForEach(deletionDestinations, id: \.id) { destination in
                Button("移到 \(displayName(for: destination))") {
                    deleteSelectedTopic(movingCardsTo: destination)
                }
                .accessibilityIdentifier(LibraryAccessibilityID.deleteDestination(destination))
            }
            Button("取消", role: .cancel) {
                clearDeletionSelection()
            }
        } message: {
            Text("该 Topic 的全部题目会先迁移到所选 Topic，再删除原 Topic。")
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
    }

    @ViewBuilder
    private func topicRow(_ topic: TopicRecord) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                TopicQuestionListView(topic: topic)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: topic))
                        .font(.body.weight(topic.systemKind == .others ? .semibold : .regular))
                    Text("\(activeCardCount(for: topic)) 道题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier(LibraryAccessibilityID.topicRow(topic))

            if topic.systemKindRaw == nil {
                Menu {
                    Button("重命名") {
                        topicToRename = topic
                        isRenamingTopic = true
                    }
                    Button("删除", role: .destructive) {
                        prepareToDelete(topic)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .accessibilityLabel("管理 \(topic.name)")
                .accessibilityIdentifier(LibraryAccessibilityID.topicActions(topic))
            }
        }
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }

    private func activeCardCount(for topic: TopicRecord) -> Int {
        topic.cards.lazy.filter { !$0.isTrashed }.count
    }

    private func prepareToDelete(_ topic: TopicRecord) {
        do {
            let destinations = try service.deletionDestinations(for: topic, context: modelContext)
            guard !destinations.isEmpty else {
                errorMessage = "没有可接收题目的 Topic。"
                return
            }
            topicToDelete = topic
            deletionDestinations = destinations
            isChoosingDeletionDestination = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedTopic(movingCardsTo destination: TopicRecord) {
        guard let topicToDelete else { return }
        do {
            try service.delete(topicToDelete, moveCardsTo: destination, context: modelContext)
            clearDeletionSelection()
        } catch {
            errorMessage = error.localizedDescription
            clearDeletionSelection()
        }
    }

    private func clearDeletionSelection() {
        topicToDelete = nil
        deletionDestinations = []
        isChoosingDeletionDestination = false
    }
}

private struct TopicQuestionListView: View {
    let topic: TopicRecord

    private var activeCards: [QuestionCardRecord] {
        topic.cards
            .filter { !$0.isTrashed }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    var body: some View {
        List(activeCards, id: \.id) { question in
            NavigationLink {
                QuestionDetailView(question: question)
            } label: {
                Text(question.questionText)
                    .lineLimit(3)
            }
            .accessibilityIdentifier(LibraryAccessibilityID.questionRow(question))
        }
        .overlay {
            if activeCards.isEmpty {
                ContentUnavailableView(
                    "暂无题目",
                    systemImage: "rectangle.stack",
                    description: Text("导入 Markdown 后，题目会显示在这里。")
                )
            }
        }
        .navigationTitle(topic.systemKind == .others ? "待分类（Others）" : topic.name)
        .toolbar {
            if topic.systemKind == .others {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        OthersView()
                    } label: {
                        Label("AI 重新分类", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("library.others.reclassify")
                }
            }
        }
    }
}
