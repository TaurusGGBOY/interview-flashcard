import SwiftData
import SwiftUI

private enum PracticeAccessibilityID {
    static let screen = "practice.screen"
    static let topicList = "practice.topic-list"
    static let includePracticed = "practice.include-practiced"
    static let start = "practice.start"
    static let card = "practice.card"
    static let skip = "practice.skip"
    static let answer = "practice.answer"
    static let changeFilters = "practice.change-filters"

    static func topic(_ id: UUID) -> String {
        "practice.topic.\(id.uuidString.lowercased())"
    }
}

struct PracticeView: View {
    private enum Phase: Equatable {
        case filters
        case card
        case empty
    }

    @Query(sort: \TopicRecord.createdAt) private var topics: [TopicRecord]
    @Query(sort: \QuestionCardRecord.activatedAt) private var cards: [QuestionCardRecord]
    @Environment(AppEnvironment.self) private var environment

    private let drawService: QuestionDrawService

    @State private var phase: Phase = .filters
    @State private var selectedTopicIDs: Set<UUID> = []
    @State private var includePracticed = false
    @State private var currentCard: QuestionCardSnapshot?
    @State private var didInitializeTopicSelection = false
    @State private var seededGenerator: SeededPracticeRandomNumberGenerator?

    init(drawService: QuestionDrawService = QuestionDrawService()) {
        self.drawService = drawService
    }

    private var orderedTopics: [TopicRecord] {
        topics.sorted { lhs, rhs in
            if lhs.systemKind == .others, rhs.systemKind != .others { return true }
            if lhs.systemKind != .others, rhs.systemKind == .others { return false }
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : comparison == .orderedAscending
        }
    }

    private var snapshots: [QuestionCardSnapshot] {
        cards.map(QuestionCardSnapshot.init(record:))
    }

    private var eligibleCards: [QuestionCardSnapshot] {
        drawService.eligibleCards(
            snapshots,
            topicIDs: selectedTopicIDs,
            includePracticed: includePracticed
        )
    }

    var body: some View {
        Group {
            switch phase {
            case .filters:
                filterView
            case .card:
                if let currentCard {
                    cardView(currentCard)
                } else {
                    emptyView
                }
            case .empty:
                emptyView
            }
        }
        .navigationTitle("练习")
        .accessibilityIdentifier(PracticeAccessibilityID.screen)
        .onAppear(perform: initializeTopicSelectionIfNeeded)
        .onChange(of: topics.map(\.id)) { _, _ in
            initializeTopicSelectionIfNeeded()
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            reconcileCurrentCard()
        }
        .onChange(of: cards.map { $0.attempts.count }) { _, _ in
            reconcileCurrentCard()
        }
    }

    private var filterView: some View {
        Form {
            Section {
                if orderedTopics.isEmpty {
                    Text("题库中还没有 Topic。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedTopics, id: \.id) { topic in
                        Toggle(isOn: topicSelectionBinding(topic.id)) {
                            HStack {
                                Text(displayName(for: topic))
                                Spacer()
                                Text("\(activeCardCount(for: topic))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier(PracticeAccessibilityID.topic(topic.id))
                    }
                }
            } header: {
                HStack {
                    Text("选择 Topic")
                    Spacer()
                    Button(selectedTopicIDs.count == orderedTopics.count ? "清空" : "全选") {
                        toggleAllTopics()
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier(PracticeAccessibilityID.topicList)

            Section {
                Toggle("包含已练习题", isOn: $includePracticed)
                    .accessibilityIdentifier(PracticeAccessibilityID.includePracticed)
            } footer: {
                Text("默认关闭。查看题目或跳过不会被记为已练习。")
            }

            Section {
                Button {
                    drawNextCard()
                } label: {
                    Label("开始练习", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier(PracticeAccessibilityID.start)
            }
        }
    }

    private func cardView(_ card: QuestionCardSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(card.topicName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(card.questionText)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                Text("满分答案会在提交回答后显示。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    AnswerEditorView(questionID: card.id)
                } label: {
                    Label("开始回答", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(PracticeAccessibilityID.answer)

                Button {
                    drawNextCard()
                } label: {
                    Label("跳过，随机抽下一题", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(PracticeAccessibilityID.skip)

                Button("调整 Topic 和练习范围") {
                    currentCard = nil
                    phase = .filters
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(PracticeAccessibilityID.changeFilters)
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PracticeAccessibilityID.card)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("当前范围没有可练习题", systemImage: "rectangle.stack.badge.minus")
        } description: {
            Text(includePracticed
                ? "所选 Topic 中没有有效题目。"
                : "所选 Topic 的题目可能都已练习过，可以调整 Topic 或开启“包含已练习题”。")
        } actions: {
            Button("调整筛选") {
                currentCard = nil
                phase = .filters
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(PracticeAccessibilityID.changeFilters)
        }
    }

    private func drawNextCard() {
        if var seededGenerator {
            currentCard = drawService.draw(from: eligibleCards, using: &seededGenerator)
            self.seededGenerator = seededGenerator
        } else {
            currentCard = drawService.draw(from: eligibleCards)
        }
        phase = currentCard == nil ? .empty : .card
    }

    private func initializeTopicSelectionIfNeeded() {
        guard !didInitializeTopicSelection, !orderedTopics.isEmpty else { return }
        selectedTopicIDs = Set(orderedTopics.map(\.id))
        if let seed = environment.launchOptions.randomSeed {
            seededGenerator = SeededPracticeRandomNumberGenerator(seed: seed)
        }
        didInitializeTopicSelection = true
    }

    private func reconcileCurrentCard() {
        guard phase == .card, let currentCard else { return }
        guard eligibleCards.contains(where: { $0.id == currentCard.id }) else {
            drawNextCard()
            return
        }
        self.currentCard = eligibleCards.first(where: { $0.id == currentCard.id })
    }

    private func topicSelectionBinding(_ topicID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTopicIDs.contains(topicID) },
            set: { isSelected in
                if isSelected {
                    selectedTopicIDs.insert(topicID)
                } else {
                    selectedTopicIDs.remove(topicID)
                }
            }
        )
    }

    private func toggleAllTopics() {
        let allIDs = Set(orderedTopics.map(\.id))
        selectedTopicIDs = selectedTopicIDs == allIDs ? [] : allIDs
    }

    private func activeCardCount(for topic: TopicRecord) -> Int {
        topic.cards.lazy.filter { !$0.isTrashed }.count
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }
}
