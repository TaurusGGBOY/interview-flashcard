import SwiftData
import SwiftUI

struct PracticeLaunchRequest: Equatable, Sendable {
    let id: UUID
    let questionID: UUID
    let startInAnswer: Bool

    init(questionID: UUID, startInAnswer: Bool, id: UUID = UUID()) {
        self.id = id
        self.questionID = questionID
        self.startInAnswer = startInAnswer
    }
}

struct PracticeView: View {
    @Query(sort: \TopicRecord.createdAt) private var topics: [TopicRecord]
    @Query(sort: \QuestionCardRecord.activatedAt) private var cards: [QuestionCardRecord]
    @Environment(AppEnvironment.self) private var environment

    private let drawService: QuestionDrawService
    private let launchRequest: PracticeLaunchRequest?
    private let onLaunchRequestConsumed: () -> Void
    private let onOpenLibrary: () -> Void

    @State private var feedState: PracticeFeedState
    @State private var currentCard: QuestionCardSnapshot?
    @State private var answeringCardID: UUID?
    @State private var historyQuestionID: UUID?
    @State private var seededGenerator: SeededPracticeRandomNumberGenerator?
    @State private var didInitializeTopicSelection = false
    @State private var lastHandledLaunchRequestID: UUID?

    init(
        drawService: QuestionDrawService = QuestionDrawService(),
        launchRequest: PracticeLaunchRequest? = nil,
        onLaunchRequestConsumed: @escaping () -> Void = {},
        onOpenLibrary: @escaping () -> Void = {}
    ) {
        self.drawService = drawService
        self.launchRequest = launchRequest
        self.onLaunchRequestConsumed = onLaunchRequestConsumed
        self.onOpenLibrary = onOpenLibrary
        _feedState = State(initialValue: Self.initialFeedState(topicIDs: []))
    }

    nonisolated static func initialFeedState(topicIDs: Set<UUID>) -> PracticeFeedState {
        PracticeFeedState(selectedTopicIDs: topicIDs, includePracticed: false)
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
            isAnswering: answeringCardID != nil,
            canUndo: canUndo,
            onSkip: skipCurrent,
            onStartAnswer: startAnswer,
            onReturnToQuestion: returnToQuestion,
            onViewHistory: viewHistory,
            onAttemptSubmitted: handleAttemptSubmitted,
            onContinueSession: finishAnswer,
            onUndo: undoLastSkip,
            onOpenLibrary: onOpenLibrary
        )
        .sheet(isPresented: historySheetBinding) {
            if let historyQuestionID,
               let question = cards.first(where: { $0.id == historyQuestionID }) {
                NavigationStack {
                    QuestionHistoryView(question: question)
                }
            } else {
                ContentUnavailableView("题目不存在", systemImage: "questionmark.folder")
            }
        }
        .accessibilityIdentifier(PracticeAccessibilityID.screen)
        .onAppear {
            initializeTopicSelectionIfNeeded()
            applyLaunchRequestIfNeeded()
        }
        .onChange(of: topics.map(\.id)) { _, _ in
            applyPersistedSettings()
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            reconcileCurrentCard()
            applyLaunchRequestIfNeeded()
        }
        .onChange(of: cards.map { $0.attempts.count }) { _, _ in
            reconcileCurrentCard()
        }
        .onChange(of: environment.practiceSettings) { _, _ in
            applyPersistedSettings()
        }
        .onChange(of: launchRequest?.id) { _, _ in
            applyLaunchRequestIfNeeded()
        }
    }

    private func initializeTopicSelectionIfNeeded() {
        guard !didInitializeTopicSelection else { return }
        let validTopicIDs = Set(topics.map(\.id))
        let settings = environment.reconcilePracticeSettings(
            validTopicIDs: validTopicIDs
        )
        feedState = PracticeFeedState(
            selectedTopicIDs: settings.resolvedTopicIDs(validTopicIDs: validTopicIDs),
            includePracticed: settings.includePracticed
        )
        didInitializeTopicSelection = true
        seededGenerator = environment.launchOptions.randomSeed.map(
            SeededPracticeRandomNumberGenerator.init(seed:)
        )
        drawNextCard()
    }

    private func applyLaunchRequestIfNeeded() {
        guard let launchRequest,
              lastHandledLaunchRequestID != launchRequest.id
        else { return }

        guard didInitializeTopicSelection else {
            initializeTopicSelectionIfNeeded()
            guard didInitializeTopicSelection else { return }
            applyLaunchRequestIfNeeded()
            return
        }

        guard let selectedCard = snapshots.first(where: {
            $0.id == launchRequest.questionID && !$0.isTrashed
        }) else {
            lastHandledLaunchRequestID = launchRequest.id
            onLaunchRequestConsumed()
            return
        }

        feedState.present(selectedCard.id)
        currentCard = selectedCard
        answeringCardID = launchRequest.startInAnswer ? selectedCard.id : nil
        historyQuestionID = nil
        lastHandledLaunchRequestID = launchRequest.id
        onLaunchRequestConsumed()
    }

    private func applyPersistedSettings() {
        guard didInitializeTopicSelection else {
            initializeTopicSelectionIfNeeded()
            return
        }
        let validTopicIDs = Set(topics.map(\.id))
        let settings = environment.reconcilePracticeSettings(
            validTopicIDs: validTopicIDs
        )
        let selectedTopicIDs = settings.resolvedTopicIDs(
            validTopicIDs: validTopicIDs
        )
        guard feedState.selectedTopicIDs != selectedTopicIDs
                || feedState.includePracticed != settings.includePracticed
        else {
            reconcileCurrentCard()
            return
        }

        feedState = PracticeFeedState(
            selectedTopicIDs: selectedTopicIDs,
            includePracticed: settings.includePracticed
        )
        currentCard = nil
        answeringCardID = nil
        drawNextCard()
    }

    private func startAnswer() {
        guard let currentCard else { return }
        answeringCardID = currentCard.id
    }

    private func returnToQuestion() {
        // Submitting an answer clears the feed state's current question so
        // the answer flow can advance normally. If the user then returns to
        // the question card, restore that identity before allowing a skip;
        // otherwise skipCurrent() has nothing to consume and the same card
        // remains on screen forever.
        if let currentCard {
            feedState.present(currentCard.id)
        }
        answeringCardID = nil
    }

    private func viewHistory() {
        guard let answeringCardID else { return }
        historyQuestionID = answeringCardID
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
        _ = feedState.answerSubmitted(questionID: questionID)
    }

    private func finishAnswer() {
        guard let questionID = answeringCardID else { return }
        answeringCardID = nil
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
        if let answeringCardID {
            currentCard = snapshots.first(where: { $0.id == answeringCardID })
            return
        }

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

    private var historySheetBinding: Binding<Bool> {
        Binding(
            get: { historyQuestionID != nil },
            set: { isPresented in
                if !isPresented { historyQuestionID = nil }
            }
        )
    }

}
