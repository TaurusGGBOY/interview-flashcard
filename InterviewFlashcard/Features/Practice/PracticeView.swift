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
    static let swipeHint = "practice.swipe-hint"
    static let skipIndicator = "practice.skip-indicator"
    static let answerIndicator = "practice.answer-indicator"
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
    @State private var dragTranslation: CGSize = .zero
    @State private var isSwipeInFlight = false
    @State private var answeringCardID: UUID?
    @State private var showSwipeHint = true

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
        .navigationDestination(item: $answeringCardID) { questionID in
            AnswerEditorView(questionID: questionID)
        }
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
        GeometryReader { geometry in
            let cardWidth = max(geometry.size.width - 32, 1)

            VStack(spacing: 18) {
                if showSwipeHint {
                    Text("左滑跳过 · 右滑开始回答")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(PracticeAccessibilityID.swipeHint)
                }

                swipeCard(card, width: cardWidth)
                    .frame(maxHeight: .infinity)

                HStack(spacing: 16) {
                    Button {
                        commitSwipe(.skip, card: card, cardWidth: cardWidth)
                    } label: {
                        Label("跳过", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isSwipeInFlight)
                    .accessibilityIdentifier(PracticeAccessibilityID.skip)

                    Button {
                        commitSwipe(.answer, card: card, cardWidth: cardWidth)
                    } label: {
                        Label("开始回答", systemImage: "pencil.and.outline")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isSwipeInFlight)
                    .accessibilityIdentifier(PracticeAccessibilityID.answer)
                }

                Button("调整 Topic 和练习范围") {
                    currentCard = nil
                    phase = .filters
                }
                .disabled(isSwipeInFlight)
                .accessibilityIdentifier(PracticeAccessibilityID.changeFilters)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func swipeCard(_ card: QuestionCardSnapshot, width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.background)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)

            VStack(alignment: .leading, spacing: 18) {
                Text(card.topicName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Divider()

                ScrollView {
                    Text(card.questionText)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                .scrollIndicators(.hidden)
            }
            .padding(24)

            swipeOverlay(cardWidth: width)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .offset(x: dragTranslation.width)
        .rotationEffect(.degrees(Double(dragTranslation.width / width) * 7))
        .simultaneousGesture(swipeGesture(for: card, cardWidth: width))
        .allowsHitTesting(!isSwipeInFlight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PracticeAccessibilityID.card)
    }

    @ViewBuilder
    private func swipeOverlay(cardWidth: CGFloat) -> some View {
        if dragTranslation.width < 0 {
            swipeIndicator(
                title: "跳过",
                systemImage: "xmark",
                color: .red
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(24)
            .opacity(swipeProgress(cardWidth: cardWidth))
            .accessibilityIdentifier(PracticeAccessibilityID.skipIndicator)
        } else if dragTranslation.width > 0 {
            swipeIndicator(
                title: "开始回答",
                systemImage: "pencil.and.outline",
                color: .green
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .opacity(swipeProgress(cardWidth: cardWidth))
            .accessibilityIdentifier(PracticeAccessibilityID.answerIndicator)
        }
    }

    private func swipeIndicator(
        title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 2))
    }

    private func swipeProgress(cardWidth: CGFloat) -> Double {
        let threshold = cardWidth * PracticeSwipeInteraction.distanceThresholdRatio
        return Double(min(abs(dragTranslation.width) / max(threshold, 1), 1))
    }

    private func swipeGesture(
        for card: QuestionCardSnapshot,
        cardWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isSwipeInFlight else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragTranslation = CGSize(width: value.translation.width, height: 0)
                showSwipeHint = false
            }
            .onEnded { value in
                guard !isSwipeInFlight else { return }
                let action = PracticeSwipeInteraction.action(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    cardWidth: cardWidth
                )
                guard let action else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dragTranslation = .zero
                    }
                    return
                }
                commitSwipe(action, card: card, cardWidth: cardWidth)
            }
    }

    private func commitSwipe(
        _ action: PracticeSwipeAction,
        card: QuestionCardSnapshot,
        cardWidth: CGFloat
    ) {
        guard !isSwipeInFlight else { return }
        isSwipeInFlight = true
        showSwipeHint = false

        let exitOffset = action == .skip
            ? -(cardWidth + 160)
            : cardWidth + 160

        withAnimation(
            .easeOut(duration: 0.22),
            completionCriteria: .logicallyComplete
        ) {
            dragTranslation = CGSize(width: exitOffset, height: 0)
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragTranslation = .zero
            }
            isSwipeInFlight = false

            switch action {
            case .skip:
                drawNextCard(excluding: card.id)
            case .answer:
                answeringCardID = card.id
            }
        }
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

    private func drawNextCard(excluding cardID: UUID? = nil) {
        let drawPool = PracticeSwipeInteraction.nextDrawPool(
            from: eligibleCards,
            excluding: cardID
        )

        if var seededGenerator {
            currentCard = drawService.draw(from: drawPool, using: &seededGenerator)
            self.seededGenerator = seededGenerator
        } else {
            currentCard = drawService.draw(from: drawPool)
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
