# Practice Swipe Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current practice question panel with a single Tinder-style card where left swipe skips and right swipe opens the existing answer editor without revealing the reference answer.

**Architecture:** Keep `QuestionDrawService` and all SwiftData entities unchanged. Add a pure `PracticeSwipeInteraction` policy for horizontal intent, threshold decisions, and immediate-repeat avoidance; `PracticeView` owns only transient drag animation and programmatic navigation to `AnswerEditorView`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, Xcode 27 beta, iOS 27.0 Simulator, Codex Computer Use through Device Hub.

## Global Constraints

- Acceptance device is only iPhone 17 Pro Max, iOS 27.0, UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`.
- The card face contains only Topic and question text. It must not contain the reference answer or copy that calls attention to the reference answer.
- Left swipe means skip and must not create an `AnswerAttemptRecord` or mark the card practiced.
- Right swipe means start answering and must navigate to `AnswerEditorView`; navigation alone must not create an attempt.
- The reference answer remains visible only after a submitted answer has completed processing.
- “包含已练习题” remains default-off, and the existing pure-random selection remains unchanged.
- A skipped card is excluded only from the immediately following draw when another eligible card exists; it remains eligible for later draws.
- Gesture actions must have visible feedback and equivalent accessible buttons.
- Use native SwiftUI only; do not add a card-stack dependency or change the data model, AI pipeline, import pipeline, or scoring rules.
- Preserve unrelated dirty-worktree changes. Every commit below stages only the files listed in its task.

## File Map

- Create `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift`: pure swipe decision and next-pool policy.
- Create `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift`: deterministic unit tests for direction, threshold, vertical rejection, velocity projection, and immediate-repeat avoidance.
- Modify `InterviewFlashcard/Features/Practice/PracticeView.swift`: single-card visual, drag feedback, buttons, animation, programmatic answer navigation, and excluded-current draw.
- Do not modify `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`: it already hides the reference answer until `processingResult` exists.
- Produce ignored evidence under `diagnostics/mac-ui/practice-swipe/` using the existing acceptance scripts.

---

### Task 1: Implement and test the pure swipe policy

**Files:**
- Create: `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift`
- Create: `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift`

**Interfaces:**
- Consumes: `QuestionCardSnapshot` from `QuestionDrawService.swift`.
- Produces: `PracticeSwipeAction`, `PracticeSwipeInteraction.action(translation:predictedEndTranslation:cardWidth:)`, and `PracticeSwipeInteraction.nextDrawPool(from:excluding:)`.

- [ ] **Step 1: Write the failing swipe-policy tests**

Create `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift` with:

```swift
import CoreGraphics
import Foundation
import XCTest

final class PracticeSwipeInteractionTests: XCTestCase {
    func testShortHorizontalDragReturnsNil() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 70, height: 4),
            predictedEndTranslation: CGSize(width: 80, height: 4),
            cardWidth: 300
        )

        XCTAssertNil(action)
    }

    func testLeftDragPastThresholdSkips() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: -100, height: 8),
            predictedEndTranslation: CGSize(width: -110, height: 8),
            cardWidth: 300
        )

        XCTAssertEqual(action, .skip)
    }

    func testRightDragPastThresholdStartsAnswer() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 100, height: 8),
            predictedEndTranslation: CGSize(width: 110, height: 8),
            cardWidth: 300
        )

        XCTAssertEqual(action, .answer)
    }

    func testVerticalDragNeverCommits() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 120, height: 180),
            predictedEndTranslation: CGSize(width: 220, height: 280),
            cardWidth: 300
        )

        XCTAssertNil(action)
    }

    func testFastHorizontalProjectionCommitsBelowDistanceThreshold() {
        let action = PracticeSwipeInteraction.action(
            translation: CGSize(width: 42, height: 5),
            predictedEndTranslation: CGSize(width: 150, height: 8),
            cardWidth: 300
        )

        XCTAssertEqual(action, .answer)
    }

    func testNextDrawPoolExcludesCurrentWhenAlternativesExist() {
        let first = snapshot(ordinal: 1)
        let second = snapshot(ordinal: 2)

        let pool = PracticeSwipeInteraction.nextDrawPool(
            from: [first, second],
            excluding: first.id
        )

        XCTAssertEqual(pool, [second])
    }

    func testNextDrawPoolFallsBackWhenCurrentIsOnlyCard() {
        let onlyCard = snapshot(ordinal: 1)

        let pool = PracticeSwipeInteraction.nextDrawPool(
            from: [onlyCard],
            excluding: onlyCard.id
        )

        XCTAssertEqual(pool, [onlyCard])
    }

    private func snapshot(ordinal: Int) -> QuestionCardSnapshot {
        QuestionCardSnapshot(
            id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", ordinal))!,
            topicID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            topicName: "后端",
            questionText: "题目 \(ordinal)",
            isTrashed: false,
            hasSubmittedAttempt: false
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails because the policy does not exist**

Run:

```bash
IF_TEST_LOG_PATH=.build/logs/practice-swipe-policy-red.log \
  scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests
```

Expected: `xcodebuild` fails to compile with `cannot find 'PracticeSwipeInteraction' in scope`.

- [ ] **Step 3: Implement the minimal pure policy**

Create `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift` with:

```swift
import CoreGraphics
import Foundation

enum PracticeSwipeAction: Equatable, Sendable {
    case skip
    case answer
}

struct PracticeSwipeInteraction: Sendable {
    static let distanceThresholdRatio: CGFloat = 0.32
    static let minimumHorizontalIntent: CGFloat = 12

    static func action(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        cardWidth: CGFloat
    ) -> PracticeSwipeAction? {
        guard cardWidth > 0 else { return nil }
        guard abs(translation.width) >= minimumHorizontalIntent else { return nil }
        guard abs(translation.width) > abs(translation.height) else { return nil }

        let threshold = cardWidth * distanceThresholdRatio
        guard abs(translation.width) >= threshold
            || abs(predictedEndTranslation.width) >= threshold
        else {
            return nil
        }

        return translation.width < 0 ? .skip : .answer
    }

    static func nextDrawPool(
        from cards: [QuestionCardSnapshot],
        excluding cardID: UUID?
    ) -> [QuestionCardSnapshot] {
        guard let cardID else { return cards }
        let alternatives = cards.filter { $0.id != cardID }
        return alternatives.isEmpty ? cards : alternatives
    }
}
```

- [ ] **Step 4: Run the policy and existing draw tests**

Run:

```bash
IF_TEST_LOG_PATH=.build/logs/practice-swipe-policy-green.log \
  scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests \
  -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests
```

Expected: `TEST SUCCEEDED`; all new policy tests and all existing pure-random draw tests pass.

- [ ] **Step 5: Commit only the policy and its tests**

```bash
git add \
  InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift \
  InterviewFlashcardTests/PracticeSwipeInteractionTests.swift
git commit -m "feat: add practice swipe policy"
```

---

### Task 2: Replace the practice panel with a draggable single card

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Verify unchanged: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`

**Interfaces:**
- Consumes: `PracticeSwipeAction` and `PracticeSwipeInteraction` from Task 1; existing `AnswerEditorView(questionID:)`; existing `QuestionDrawService.draw` methods.
- Produces: left-swipe skip, right-swipe answer navigation, equivalent buttons, and stable accessibility identifiers under `PracticeAccessibilityID`.

- [ ] **Step 1: Add accessibility IDs and transient view state**

Add the following identifiers to `PracticeAccessibilityID`:

```swift
static let swipeHint = "practice.swipe-hint"
static let skipIndicator = "practice.skip-indicator"
static let answerIndicator = "practice.answer-indicator"
```

Add these `@State` properties beside the existing practice state:

```swift
@State private var dragTranslation: CGSize = .zero
@State private var isSwipeInFlight = false
@State private var answeringCardID: UUID?
@State private var showSwipeHint = true
```

- [ ] **Step 2: Add programmatic answer navigation**

Attach this destination to the outer `Group` in `body`, after the existing `navigationTitle` modifier:

```swift
.navigationDestination(item: $answeringCardID) { questionID in
    AnswerEditorView(questionID: questionID)
}
```

Do not create an attempt in the destination or swipe handler. `AnswerSubmissionService` remains the only component that creates `AnswerAttemptRecord` after explicit user submission.

- [ ] **Step 3: Replace `cardView(_:)` with the single-card layout**

Replace the existing `cardView(_:)` implementation with:

```swift
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
```

This removes the existing `NavigationLink`, the old stacked buttons, and the sentence `满分答案会在提交回答后显示。` from the card face.

- [ ] **Step 4: Add the card visual, overlays, and gesture**

Add these helpers inside `PracticeView` immediately after `cardView(_:)`:

```swift
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
```

- [ ] **Step 5: Add one shared commit path for gestures and buttons**

Add this method after the gesture helper:

```swift
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
```

Both bottom buttons and `DragGesture.onEnded` must call this method. No other skip or answer navigation path should remain in `cardView(_:)`.

- [ ] **Step 6: Exclude the skipped card only from the immediate next draw**

Replace the existing `drawNextCard()` signature and first line of pool selection with:

```swift
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
```

Existing callers continue using `drawNextCard()`; only a completed skip calls `drawNextCard(excluding: card.id)`.

- [ ] **Step 7: Run focused regression tests and build the app**

Run:

```bash
IF_TEST_LOG_PATH=.build/logs/practice-swipe-ui.log \
  scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests \
  -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests \
  -only-testing:InterviewFlashcardTests/AnswerSubmissionServiceTests
```

Expected: `TEST SUCCEEDED`.

Then run:

```bash
IF_BUILD_LOG_PATH=.build/logs/practice-swipe-build.log \
IF_LAUNCH_LOG_PATH=.build/logs/practice-swipe-launch.log \
  scripts/dev/build-and-launch.sh \
  --ai stub \
  --stub-mode success \
  --speech unsupported \
  --fixture practice-mixed \
  --random-seed 20260805
```

Expected: `BUILD SUCCEEDED`; the app installs and launches as `com.gaoguobin.InterviewFlashcard` on the pinned iPhone 17 Pro Max.

- [ ] **Step 8: Commit only the practice view change**

```bash
git add InterviewFlashcard/Features/Practice/PracticeView.swift
git commit -m "feat: add swipeable practice card"
```

---

### Task 3: Run the full regression suite

**Files:**
- Verify: all `InterviewFlashcardTests/*.swift`
- Output: `.build/logs/practice-swipe-full-tests.log`

**Interfaces:**
- Consumes: committed Task 1 and Task 2 code.
- Produces: a complete `xcodebuild test` result before UI acceptance.

- [ ] **Step 1: Run the full test target**

```bash
IF_TEST_LOG_PATH=.build/logs/practice-swipe-full-tests.log \
  scripts/dev/test.sh
```

Expected: `TEST SUCCEEDED`, including `PracticeSwipeInteractionTests`, existing random-draw tests, answer submission/processing tests, voice gating tests, persistence tests, end-to-end tests, and privacy tests.

- [ ] **Step 2: Inspect the feature-only diff**

```bash
git diff HEAD~2 -- \
  InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift \
  InterviewFlashcard/Features/Practice/PracticeView.swift \
  InterviewFlashcardTests/PracticeSwipeInteractionTests.swift
```

Verify all of these invariants in the diff:

- no reference-answer text exists in the practice card;
- `.skip` never calls `AnswerSubmissionService`;
- `.answer` only sets `answeringCardID`;
- both buttons call `commitSwipe`;
- vertical drags return `nil`;
- the existing `includePracticed` default remains `false`;
- `QuestionDrawService` and persistence models are unchanged.

- [ ] **Step 3: Confirm the worktree did not gain unrelated staged files**

```bash
git status --short
git diff --cached --name-only
```

Expected: no files are staged. Pre-existing unrelated modifications may remain unstaged and must not be altered or committed.

---

### Task 4: Verify the complete interaction through Computer Use

**Files:**
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/context.txt`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/tests.log`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/build.log`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/launch.log`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/steps.md`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/before.png`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/after.png`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/state-after-skip.json`
- Create ignored evidence: `diagnostics/mac-ui/practice-swipe/state.json`

**Interfaces:**
- Consumes: current committed checkout, `practice-mixed` fixture, deterministic AI stub, Device Hub app `com.apple.dt.Devices`, and acceptance scripts.
- Produces: visible and independent-state evidence that left swipe skips without an attempt, right swipe opens the answer editor without a reference answer, submission creates exactly one new attempt, and buttons match gesture behavior.

- [ ] **Step 1: Start a clean acceptance run and save the full-suite result**

```bash
scripts/dev/preflight.sh
scripts/acceptance/start-run.sh practice-swipe
IF_TEST_LOG_PATH=diagnostics/mac-ui/practice-swipe/tests.log \
  scripts/dev/test.sh
```

Expected: preflight prints `READY`; `tests.log` contains `TEST SUCCEEDED`; `context.txt` records a HEAD that contains both feature commits and the iPhone 17 Pro Max UDID.

- [ ] **Step 2: Build and launch the deterministic fixture into the pinned device**

```bash
IF_BUILD_LOG_PATH=diagnostics/mac-ui/practice-swipe/build.log \
IF_LAUNCH_LOG_PATH=diagnostics/mac-ui/practice-swipe/launch.log \
  scripts/dev/build-and-launch.sh \
  --ai stub \
  --stub-mode success \
  --speech unsupported \
  --fixture practice-mixed \
  --random-seed 20260805
```

Expected: build log contains `BUILD SUCCEEDED`; launch log records `fixture=practice-mixed`, `random_seed=20260805`, bundle ID `com.gaoguobin.InterviewFlashcard`, and the pinned UDID.

- [ ] **Step 3: Inspect Device Hub and capture the before screenshot**

Use `mcp__node_repl__js` to initialize Computer Use once, then call `sky.get_app_state({ app: "com.apple.dt.Devices" })`. Confirm Device Hub is foreground, `iPhone 17 Pro Max` is selected, and the app is on the practice filter page.

Before every following click, drag, type, scroll, or key press, call `sky.get_app_state` again. Select all Topics, leave “包含已练习题” off, click “开始练习”, and confirm:

- exactly one large question card is visible;
- the card contains Topic and question text;
- the text `满分答案` is absent;
- the hint `左滑跳过 · 右滑开始回答` is visible;
- “跳过” and “开始回答” buttons are visible.

Trigger `Cmd+Shift+3` through `sky.press_key`, then run:

```bash
scripts/acceptance/collect-screenshot.sh practice-swipe before
```

- [ ] **Step 4: Perform a real left drag and prove it did not create an attempt**

With a fresh Device Hub state, call `sky.drag({ app: "com.apple.dt.Devices", from_x, from_y, to_x, to_y })` from the card center to more than 32% of its width toward the left. Confirm a different question is visible after the exit animation. `sky.drag` is atomic, so do not claim that a post-action accessibility tree proves the transient red overlay; the evidence for this step is the real Computer Use drag action, the changed visible question, the before screenshot showing the gesture legend, and the state readback below.

Run:

```bash
scripts/acceptance/read-state.sh practice-swipe
mv \
  diagnostics/mac-ui/practice-swipe/state.json \
  diagnostics/mac-ui/practice-swipe/state-after-skip.json
```

Expected: `state-after-skip.json` still contains the fixture's single pre-seeded attempt; skipping created no second attempt.

- [ ] **Step 5: Perform a real right drag and verify the answer page**

With a fresh Device Hub state, call `sky.drag({ app: "com.apple.dt.Devices", from_x, from_y, to_x, to_y })` from the card center to more than 32% of its width toward the right. Confirm the app navigates to `AnswerEditorView` for the same question. As above, record the real drag call and destination instead of claiming that the post-action tree captured the transient green overlay.

On the answer page confirm:

- the question is visible;
- the text editor and “提交文字回答” button are visible;
- the local-transcription button is disabled under `--speech unsupported`;
- no reference answer or `满分答案` section is visible before submission.

- [ ] **Step 6: Submit text and verify the result appears only afterward**

Type `URLSession 负责发送网络请求，应该处理错误、状态码和解码。` into the text editor and click “提交文字回答”. Wait by repeatedly reading fresh Device Hub state until processing finishes.

Confirm the result page contains:

- a total score;
- all six score dimensions;
- the reference-answer section only after the submitted result exists.

Return to the practice page and confirm the submitted question is no longer the current card while “包含已练习题” remains off.

- [ ] **Step 7: Verify the two button alternatives**

Use the visible “跳过” button once and confirm a new card appears. Use “开始回答” once and confirm it opens `AnswerEditorView` without a pre-submit reference answer. Return without submitting so this button check creates no extra attempt.

- [ ] **Step 8: Capture final evidence and read final state**

Return from the unsubmitted button check, open the `历史` tab, select the text attempt created in Step 6, and confirm its result page. Trigger `Cmd+Shift+3` through Computer Use, and run:

```bash
scripts/acceptance/collect-screenshot.sh practice-swipe after
scripts/acceptance/read-state.sh practice-swipe
```

Expected: final `state.json` contains exactly two attempts: the fixture's original attempt plus the one text attempt submitted in Step 6. It contains a polish result and evaluation for the new attempt and contains no API Key.

- [ ] **Step 9: Record the actions and finish the evidence contract**

Edit `diagnostics/mac-ui/practice-swipe/steps.md` to record the exact visible questions before/after each action, the absence of a pre-submit reference answer, attempt counts from both JSON files, the six-dimension result, and any exception. Set the last line to:

```markdown
- Acceptance result: PASS
```

Then run:

```bash
scripts/acceptance/finish-run.sh practice-swipe
```

Expected: `PASS: acceptance evidence is complete for practice-swipe`.

## Completion Criteria

The feature is complete only when Tasks 1–4 are all checked, both feature commits exist, the full XCTest target passes, the current build launches on the pinned iPhone 17 Pro Max, Computer Use performs both real drag directions and both button alternatives, `state-after-skip.json` proves skip did not create an attempt, final `state.json` proves submission created exactly one attempt, and the reference answer is absent before submission but present after scoring.
