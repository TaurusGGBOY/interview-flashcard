import SwiftData
import SwiftUI

struct PracticeView: View {
    @Query(sort: \TopicRecord.createdAt) private var topics: [TopicRecord]
    @Query(sort: \QuestionCardRecord.activatedAt) private var cards: [QuestionCardRecord]
    @Environment(AppEnvironment.self) private var environment

    private let drawService: QuestionDrawService
    private let onOpenLibrary: () -> Void

    @State private var feedState: PracticeFeedState
    @State private var currentCard: QuestionCardSnapshot?
    @State private var answeringCardID: UUID?
    @State private var seededGenerator: SeededPracticeRandomNumberGenerator?
    @State private var isFilterPresented = false
    @State private var didInitializeTopicSelection = false
    @State private var didApplyFilter = false

    init(
        drawService: QuestionDrawService = QuestionDrawService(),
        onOpenLibrary: @escaping () -> Void = {}
    ) {
        self.drawService = drawService
        self.onOpenLibrary = onOpenLibrary
        _feedState = State(initialValue: Self.initialFeedState(topicIDs: []))
    }

    nonisolated static func initialFeedState(topicIDs: Set<UUID>) -> PracticeFeedState {
        PracticeFeedState(selectedTopicIDs: topicIDs, includePracticed: false)
    }

    nonisolated static func applyFilter(
        _ selection: PracticeFilterSelection,
        to feedState: inout PracticeFeedState
    ) {
        feedState.selectedTopicIDs = selection.selectedTopicIDs
        feedState.includePracticed = selection.includePracticed
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

    private var topicOptions: [PracticeTopicOption] {
        orderedTopics.map {
            PracticeTopicOption(
                id: $0.id,
                title: displayName(for: $0),
                activeCardCount: activeCardCount(for: $0)
            )
        }
    }

    private var snapshots: [QuestionCardSnapshot] {
        cards.map(QuestionCardSnapshot.init(record:))
    }

    private var eligibleCards: [QuestionCardSnapshot] {
        drawService.eligibleCards(
            snapshots,
            topicIDs: feedState.selectedTopicIDs,
            includePracticed: feedState.includePracticed
        )
    }

    private var totalActiveCardCount: Int {
        snapshots.lazy.filter { !$0.isTrashed }.count
    }

    private var emptyReason: PracticeFeedEmptyReason? {
        guard didInitializeTopicSelection else { return nil }
        return feedState.emptyReason(
            totalActiveCount: totalActiveCardCount,
            eligibleCount: eligibleCards.count
        )
    }

    private var canUndo: Bool {
        guard case .skipped = feedState.lastAction else { return false }
        return true
    }

    var body: some View {
        PracticeFeedView(
            card: currentCard,
            emptyReason: emptyReason,
            isInteractionDisabled: answeringCardID != nil,
            canUndo: canUndo,
            onSkip: skipCurrent,
            onStartAnswer: startAnswer,
            onUndo: undoLastSkip,
            onOpenFilter: { isFilterPresented = true },
            onOpenLibrary: onOpenLibrary
        )
        .navigationTitle("练习")
        .navigationDestination(item: $answeringCardID) { questionID in
            AnswerEditorView(
                questionID: questionID,
                onAttemptSubmitted: handleAttemptSubmitted,
                onContinueSession: { answeringCardID = nil }
            )
        }
        .sheet(isPresented: $isFilterPresented) {
            PracticeFilterSheet(
                topics: topicOptions,
                initialSelection: PracticeFilterSelection(
                    selectedTopicIDs: feedState.selectedTopicIDs,
                    includePracticed: feedState.includePracticed
                ),
                onApply: applyFilter
            )
        }
        .accessibilityIdentifier(PracticeAccessibilityID.screen)
        .onAppear(perform: initializeTopicSelectionIfNeeded)
        .onChange(of: topics.map(\.id)) { _, _ in
            initializeTopicSelectionIfNeeded()
            refreshDefaultTopicSelectionIfNeeded()
            reconcileCurrentCard()
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            refreshDefaultTopicSelectionIfNeeded()
            reconcileCurrentCard()
        }
        .onChange(of: cards.map { $0.attempts.count }) { _, _ in
            reconcileCurrentCard()
        }
    }

    private func applyFilter(_ selection: PracticeFilterSelection) {
        var updated = feedState
        Self.applyFilter(selection, to: &updated)
        didApplyFilter = true

        // A filter operation is one atomic state transition: the old card and
        // undo affordance are discarded before the next card is drawn.
        feedState = PracticeFeedState(
            selectedTopicIDs: updated.selectedTopicIDs,
            includePracticed: updated.includePracticed
        )
        currentCard = nil
        answeringCardID = nil
        drawNextCard()
    }

    private func initializeTopicSelectionIfNeeded() {
        guard !didInitializeTopicSelection else { return }
        let activeTopicIDs = orderedTopics
            .filter { activeCardCount(for: $0) > 0 }
            .map(\.id)
        feedState = Self.initialFeedState(topicIDs: Set(activeTopicIDs))
        didInitializeTopicSelection = true
        seededGenerator = environment.launchOptions.randomSeed.map(
            SeededPracticeRandomNumberGenerator.init(seed:)
        )
        drawNextCard()
    }

    private func refreshDefaultTopicSelectionIfNeeded() {
        guard !didApplyFilter else { return }
        let activeTopicIDs = Set(
            orderedTopics
                .filter { activeCardCount(for: $0) > 0 }
                .map(\.id)
        )
        guard feedState.selectedTopicIDs != activeTopicIDs else { return }
        feedState.selectedTopicIDs = activeTopicIDs
    }

    private func startAnswer() {
        guard let currentCard else { return }
        answeringCardID = currentCard.id
    }

    private func skipCurrent() {
        guard currentCard != nil, feedState.skipCurrent() != nil else { return }
        currentCard = nil
        drawNextCard(excluding: lastActionQuestionID)
    }

    private func undoLastSkip() {
        guard let restoredID = feedState.undoLastSkip(),
              let restoredCard = snapshots.first(where: { $0.id == restoredID })
        else { return }
        currentCard = restoredCard
    }

    private func handleAttemptSubmitted(_ questionID: UUID) {
        guard feedState.answerSubmitted(questionID: questionID) else { return }
        currentCard = nil
        drawNextCard(excluding: questionID)
    }

    private var lastActionQuestionID: UUID? {
        switch feedState.lastAction {
        case let .skipped(questionID), let .answered(questionID): questionID
        case nil: nil
        }
    }

    private func drawNextCard(excluding cardID: UUID? = nil) {
        guard didInitializeTopicSelection, currentCard == nil else { return }

        let pool = PracticeSwipeInteraction.nextDrawPool(
            from: eligibleCards,
            excluding: cardID
        )
        let drawn: QuestionCardSnapshot?
        if var seededGenerator {
            drawn = drawService.draw(from: pool, using: &seededGenerator)
            self.seededGenerator = seededGenerator
        } else {
            drawn = drawService.draw(from: pool)
        }

        guard let drawn else { return }
        feedState.present(drawn.id)
        currentCard = drawn
    }

    private func reconcileCurrentCard() {
        guard let currentCard else {
            drawNextCard(excluding: lastActionQuestionID)
            return
        }

        guard eligibleCards.contains(where: { $0.id == currentCard.id }) else {
            self.currentCard = nil
            feedState = PracticeFeedState(
                selectedTopicIDs: feedState.selectedTopicIDs,
                includePracticed: feedState.includePracticed
            )
            drawNextCard(excluding: currentCard.id)
            return
        }

        self.currentCard = eligibleCards.first(where: { $0.id == currentCard.id })
    }

    private func activeCardCount(for topic: TopicRecord) -> Int {
        topic.cards.lazy.filter { !$0.isTrashed }.count
    }

    private func displayName(for topic: TopicRecord) -> String {
        topic.systemKind == .others ? "待分类（Others）" : topic.name
    }
}
