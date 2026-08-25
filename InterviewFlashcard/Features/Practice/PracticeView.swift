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

private struct PracticeCardRevision: Equatable {
    let id: UUID
    let trashedAt: Date?
    let attemptCount: Int

    init(record: QuestionCardRecord) {
        id = record.id
        trashedAt = record.trashedAt
        attemptCount = record.attempts.count
    }
}

struct PracticeView: View {
    @Query(sort: \TopicRecord.createdAt) private var topics: [TopicRecord]
    @Query(sort: \QuestionCardRecord.activatedAt) private var cards: [QuestionCardRecord]
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext

    private let launchRequest: PracticeLaunchRequest?
    private let onLaunchRequestConsumed: () -> Void
    private let onOpenLibrary: () -> Void

    @State private var feedState: PracticeFeedState
    @State private var currentCard: QuestionCardSnapshot?
    @State private var answeringCardID: UUID?
    @State private var historyQuestionID: UUID?
    @State private var cachedSnapshots: [QuestionCardSnapshot] = []
    @State private var cardBuffer = PracticeCardBuffer()
    @State private var isProducingCards = false
    @State private var isCardBufferExhausted = false
    @State private var eligibleCardCount = 0
    @State private var activeCardCount = 0
    @State private var seededGenerator: SeededPracticeRandomNumberGenerator?
    @State private var activeOrderMode: PracticeOrderMode = .random
    @State private var practiceSequenceKey: String?
    @State private var progressBeforeLastAction: UUID?
    @State private var isPersistingDelete = false
    @State private var didInitializeTopicSelection = false
    @State private var lastHandledLaunchRequestID: UUID?
    @State private var errorMessage: String?

    init(
        launchRequest: PracticeLaunchRequest? = nil,
        onLaunchRequestConsumed: @escaping () -> Void = {},
        onOpenLibrary: @escaping () -> Void = {}
    ) {
        self.launchRequest = launchRequest
        self.onLaunchRequestConsumed = onLaunchRequestConsumed
        self.onOpenLibrary = onOpenLibrary
        _feedState = State(initialValue: Self.initialFeedState(topicIDs: []))
    }

    nonisolated static func initialFeedState(topicIDs: Set<UUID>) -> PracticeFeedState {
        PracticeFeedState(selectedTopicIDs: topicIDs, includePracticed: false)
    }

    private var emptyReason: PracticeFeedEmptyReason? {
        guard didInitializeTopicSelection else { return nil }
        return feedState.emptyReason(
            totalActiveCount: activeCardCount,
            eligibleCount: eligibleCardCount
        )
    }

    private var undoTitle: String? {
        switch feedState.lastAction {
        case .skipped:
            "撤销跳过"
        case .deleted:
            "撤销删除"
        case .answered, nil:
            nil
        }
    }

    var body: some View {
        PracticeFeedView(
            card: currentCard,
            emptyReason: emptyReason,
            isAnswering: answeringCardID != nil,
            isInteractionDisabled: isPersistingDelete,
            undoTitle: undoTitle,
            onSkip: skipCurrent,
            onDelete: deleteCurrent,
            onStartAnswer: startAnswer,
            onReturnToQuestion: returnToQuestion,
            onViewHistory: viewHistory,
            onAttemptSubmitted: handleAttemptSubmitted,
            onContinueSession: finishAnswer,
            onUndo: undoLastAction,
            onOpenLibrary: onOpenLibrary
        )
        .alert("无法完成操作", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
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
            refreshSnapshotCache()
            initializeTopicSelectionIfNeeded()
            applyLaunchRequestIfNeeded()
        }
        .onChange(of: topics.map(\.id)) { _, _ in
            applyPersistedSettings()
        }
        .onChange(of: cards.map(PracticeCardRevision.init(record:))) { oldValue, newValue in
            handleCardRevisionsChanged(from: oldValue, to: newValue)
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
        let sequenceKey = Self.sequenceKey(
            topicIDs: settings.resolvedTopicIDs(validTopicIDs: validTopicIDs),
            includePracticed: settings.includePracticed,
            orderMode: settings.orderMode
        )
        if settings.progressSequenceKey != sequenceKey {
            environment.clearPracticeProgress()
        }
        activeOrderMode = settings.orderMode
        practiceSequenceKey = sequenceKey
        feedState = PracticeFeedState(
            selectedTopicIDs: settings.resolvedTopicIDs(validTopicIDs: validTopicIDs),
            includePracticed: settings.includePracticed
        )
        didInitializeTopicSelection = true
        seededGenerator = environment.launchOptions.randomSeed.map(
            SeededPracticeRandomNumberGenerator.init(seed:)
        )
        refreshPracticeCounts()
        invalidateCardBuffer(clearUpcoming: true)
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

        guard let selectedCard = cachedSnapshots.first(where: {
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
        invalidateCardBuffer(clearUpcoming: true)
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
        let nextSequenceKey = Self.sequenceKey(
            topicIDs: selectedTopicIDs,
            includePracticed: settings.includePracticed,
            orderMode: settings.orderMode
        )
        guard feedState.selectedTopicIDs != selectedTopicIDs
                || feedState.includePracticed != settings.includePracticed
                || activeOrderMode != settings.orderMode
        else {
            reconcileCurrentCard()
            return
        }

        feedState = PracticeFeedState(
            selectedTopicIDs: selectedTopicIDs,
            includePracticed: settings.includePracticed
        )
        activeOrderMode = settings.orderMode
        practiceSequenceKey = nextSequenceKey
        progressBeforeLastAction = nil
        currentCard = nil
        answeringCardID = nil
        refreshPracticeCounts()
        invalidateCardBuffer(clearUpcoming: true)
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
        guard let currentCard, feedState.skipCurrent() != nil else { return }
        saveProgress(afterConsuming: currentCard.id)
        self.currentCard = nil
        drawNextCard()
    }

    private func deleteCurrent() {
        guard let currentCard,
              !isPersistingDelete,
              answeringCardID == nil,
              feedState.currentQuestionID == currentCard.id,
              let currentRecord = cards.first(where: { $0.id == currentCard.id })
        else { return }

        guard feedState.deleteCurrent() != nil else { return }
        saveProgress(afterConsuming: currentCard.id)
        isPersistingDelete = true
        self.currentCard = nil
        drawNextCard()

        Task { @MainActor in
            await Task.yield()
            do {
                try TrashService().moveToTrash(card: currentRecord, context: modelContext)
            } catch {
                _ = feedState.undoLastDelete()
                restoreProgressBeforeLastAction()
                self.currentCard = currentCard
                errorMessage = error.localizedDescription
            }
            isPersistingDelete = false
        }
    }

    private func undoLastAction() {
        switch feedState.lastAction {
        case .skipped:
            guard let restoredID = feedState.undoLastSkip(),
                  let restoredCard = cachedSnapshots.first(where: { $0.id == restoredID })
            else { return }
            restoreProgressBeforeLastAction()
            cardBuffer.remove(questionID: restoredID)
            currentCard = restoredCard
            requestCardProductionIfNeeded()
        case let .deleted(questionID):
            do {
                guard let restoredRecord = cards.first(where: { $0.id == questionID }) else {
                    throw TrashService.TrashError.questionNotFound
                }
                try TrashService().restore(card: restoredRecord, context: modelContext)
                guard let restoredID = feedState.undoLastDelete(),
                      let restoredCard = cachedSnapshots.first(where: { $0.id == restoredID })
                else { return }
                restoreProgressBeforeLastAction()
                cardBuffer.remove(questionID: restoredID)
                currentCard = restoredCard
                requestCardProductionIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .answered, nil:
            break
        }
    }

    private func handleAttemptSubmitted(_ questionID: UUID) {
        _ = feedState.answerSubmitted(questionID: questionID)
    }

    private func finishAnswer() {
        guard let questionID = answeringCardID else { return }
        saveProgress(afterConsuming: questionID)
        answeringCardID = nil
        currentCard = nil
        drawNextCard()
    }

    private func drawNextCard() {
        guard didInitializeTopicSelection, currentCard == nil else { return }

        guard let drawn = cardBuffer.consume() else {
            requestCardProductionIfNeeded()
            return
        }
        isCardBufferExhausted = false
        feedState.present(drawn.id)
        currentCard = drawn
        requestCardProductionIfNeeded()
    }

    private func reconcileCurrentCard() {
        if let answeringCardID {
            currentCard = cachedSnapshots.first(where: { $0.id == answeringCardID })
            return
        }

        guard let currentCard else {
            drawNextCard()
            return
        }

        guard let refreshedCard = cachedSnapshots.first(where: {
            $0.id == currentCard.id && isEligibleForCurrentPractice($0)
        }) else {
            self.currentCard = nil
            feedState = PracticeFeedState(
                selectedTopicIDs: feedState.selectedTopicIDs,
                includePracticed: feedState.includePracticed
            )
            drawNextCard()
            return
        }

        self.currentCard = refreshedCard
    }

    private func refreshSnapshotCache() {
        cachedSnapshots = cards.map(QuestionCardSnapshot.init(record:))
    }

    private func handleCardRevisionsChanged(
        from oldValue: [PracticeCardRevision],
        to newValue: [PracticeCardRevision]
    ) {
        let oldIDs = oldValue.map(\.id)
        let newIDs = newValue.map(\.id)
        if oldIDs != newIDs || cachedSnapshots.count != cards.count {
            refreshSnapshotCache()
        } else {
            let oldByID = Dictionary(uniqueKeysWithValues: oldValue.map { ($0.id, $0) })
            let changedIDs = Set(newValue.compactMap { revision in
                oldByID[revision.id] == revision ? nil : revision.id
            })
            if !changedIDs.isEmpty {
                let changedRecords = Dictionary(uniqueKeysWithValues: cards.compactMap { record in
                    changedIDs.contains(record.id) ? (record.id, record) : nil
                })
                for index in cachedSnapshots.indices {
                    let id = cachedSnapshots[index].id
                    if let record = changedRecords[id] {
                        cachedSnapshots[index] = QuestionCardSnapshot(record: record)
                    }
                }
            }
        }

        refreshPracticeCounts()
        invalidateCardBuffer(clearUpcoming: false)
        reconcileCurrentCard()
        applyLaunchRequestIfNeeded()
    }

    private func refreshPracticeCounts() {
        activeCardCount = cachedSnapshots.lazy.filter { !$0.isTrashed }.count
        eligibleCardCount = cachedSnapshots.lazy.filter(isEligibleForCurrentPractice).count
    }

    private func isEligibleForCurrentPractice(_ card: QuestionCardSnapshot) -> Bool {
        !card.isTrashed
            && feedState.selectedTopicIDs.contains(card.topicID)
            && (feedState.includePracticed || !card.hasSubmittedAttempt)
    }

    private func invalidateCardBuffer(clearUpcoming: Bool) {
        let nextGeneration = cardBuffer.generation &+ 1
        if clearUpcoming {
            cardBuffer.reset(generation: nextGeneration)
        } else {
            let eligibleIDs = Set(cachedSnapshots.lazy.filter(isEligibleForCurrentPractice).map(\.id))
            cardBuffer.rebase(
                generation: nextGeneration,
                retaining: eligibleIDs
            )
        }
        isProducingCards = false
        isCardBufferExhausted = false
        requestCardProductionIfNeeded()
    }

    private func requestCardProductionIfNeeded() {
        guard didInitializeTopicSelection,
              !isProducingCards,
              !isCardBufferExhausted,
              cardBuffer.count < PracticeCardBuffer.capacity
        else { return }

        let generation = cardBuffer.generation
        let progressQuestionID = activeOrderMode == .random
            ? nil
            : environment.practiceSettings.progressSequenceKey == practiceSequenceKey
                ? environment.practiceSettings.progressQuestionID
                : nil
        let request = PracticeCardProductionRequest(
            generation: generation,
            snapshots: cachedSnapshots,
            selectedTopicIDs: feedState.selectedTopicIDs,
            includePracticed: feedState.includePracticed,
            orderMode: activeOrderMode,
            progressQuestionID: progressQuestionID,
            currentQuestionID: currentCard?.id,
            queuedQuestionIDs: cardBuffer.questionIDs,
            desiredCount: PracticeCardBuffer.capacity - cardBuffer.count,
            seededGenerator: seededGenerator
        )
        isProducingCards = true

        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                PracticeCardProducer().produce(request)
            }.value

            guard cardBuffer.generation == generation else { return }
            isProducingCards = false
            seededGenerator = result.seededGenerator
            if result.cards.isEmpty {
                isCardBufferExhausted = true
            } else {
                _ = cardBuffer.apply(result)
            }

            if currentCard == nil && answeringCardID == nil {
                drawNextCard()
            }
        }
    }

    private var historySheetBinding: Binding<Bool> {
        Binding(
            get: { historyQuestionID != nil },
            set: { isPresented in
                if !isPresented { historyQuestionID = nil }
            }
        )
    }

    private func saveProgress(afterConsuming questionID: UUID) {
        guard activeOrderMode != .random,
              let practiceSequenceKey
        else { return }
        progressBeforeLastAction = environment.practiceSettings.progressQuestionID
        environment.savePracticeProgress(
            sequenceKey: practiceSequenceKey,
            questionID: questionID
        )
    }

    private func restoreProgressBeforeLastAction() {
        guard let practiceSequenceKey else { return }
        environment.restorePracticeProgress(
            sequenceKey: practiceSequenceKey,
            questionID: progressBeforeLastAction
        )
        progressBeforeLastAction = nil
    }

    private static func sequenceKey(
        topicIDs: Set<UUID>,
        includePracticed: Bool,
        orderMode: PracticeOrderMode
    ) -> String {
        [
            orderMode.rawValue,
            includePracticed ? "include-practiced" : "unpracticed-only",
            topicIDs.map(\.uuidString).sorted().joined(separator: ",")
        ].joined(separator: "|")
    }

}
