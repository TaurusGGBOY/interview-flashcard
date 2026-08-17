# iPhone 17 Pro Max Full-Screen Learning Card Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the compatibility-mode black bands on iPhone 17 Pro Max and refactor practice into a full-screen, finite learning-card flow with scope selection, one visible question card, left-swipe skip, right-swipe answer, undo, keyboard-safe answering, layered AI results, and an explicit session completion state.

**Architecture:** Treat the launch metadata fix as a prerequisite, then keep `PracticeView` as a coordinator over pure transient `PracticeSessionState`. Split scope, session, swipe layer, question card, answer composer, result, and completion into focused SwiftUI views. Reuse the existing `QuestionDrawService`, `PracticeSwipeInteraction`, `AnswerSubmissionService`, `AnswerProcessingService`, SwiftData records, history, and deterministic diagnostic harness; do not change persistence or AI schemas.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, XcodeGen, Xcode 27 beta, iOS 27.0 Simulator, iPhone 17 Pro Max, Codex Computer Use through Xcode Device Hub.

## Execution status (2026-08-05)

Implemented and verified inline on iPhone 17 Pro Max (iOS 27.0, UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`). Full tests passed (84 tests), the final build passed, and `scripts/acceptance/run-final-checks.sh` passed with these Computer Use evidence runs: `iphone17-fullscreen`, `practice-swipe`, `practice-session-layout`, `practice-undo-accessibility`, `practice-session-complete`, `answer-composer-iphone17`, `answer-result-success`, and `answer-result-failure`. Commit steps remain intentionally unexecuted so the existing user-owned dirty worktree is preserved.

## Global Constraints

- Acceptance device is only iPhone 17 Pro Max, iOS 27.0, UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`.
- The Simulator viewport contract is 440 × 956 points at 3×, producing a 1320 × 2868 pixel device screenshot. Layout code must not hardcode either size.
- The current black bands are a compatibility-mode defect: the built app lacks generated `UILaunchScreen` and `UIApplicationSceneManifest` metadata, and the application target resolves to `TARGETED_DEVICE_FAMILY = 1,2`. Fix target metadata before tuning SwiftUI spacing.
- App backgrounds may use `.ignoresSafeArea()`; question text, controls, navigation, and gestures must remain inside the safe area. Never use `.ignoresSafeArea()` to stretch interactive content under the Dynamic Island or home indicator.
- Keep the five root tabs: 练习、题库、历史、统计、设置. This plan changes only the flow under 练习 and its answer/result destinations.
- Show exactly one current question card. The card face contains Topic, question text, and session progress; it never contains the full-score answer, prior score, long analysis, or AI advice.
- Left swipe means skip. It advances the finite session but creates no `AnswerAttemptRecord`, does not mark the card practiced, and offers one free three-second undo.
- Right swipe means start answering. Navigation alone creates no attempt and does not advance progress; only a persisted text answer or confirmed local transcript counts as answered.
- Gesture and visible-button paths call the same `skip` and `startAnswer` actions.
- Keep pure-random drawing. Do not introduce weak-topic weighting, FSRS, recommendations, card-stack prediction, or spaced-repetition scheduling.
- “包含已练习题” remains an explicit scope option and defaults to off for every new session.
- Sessions are transient UI state, default to 10 questions, allow 5/10/20, and are not persisted. A session ends at its target or early when the eligible pool is exhausted after submitted answers.
- Preserve the existing pipeline: save immutable raw answer → AI polish → six-dimensional evaluation → result/history. Evaluation failure must retain the raw attempt and must not become a zero score.
- When local speech transcription is unavailable, show a noninteractive availability note and no tappable recording control. Do not fall back to cloud transcription.
- Use semantic system colors, SF Symbols, Dynamic Type text styles, minimum 44 × 44 pt targets, VoiceOver custom actions, Voice Control labels, and Reduce Motion behavior.
- Use native SwiftUI. Add no swipe-card, layout, analytics, or animation dependency.
- Preserve unrelated dirty-worktree changes. Each commit stages only the files listed in its task; if a listed file contains pre-existing edits, inspect the diff and stage only this plan's hunks.
- Every user-visible task requires both automated tests and Computer Use evidence. The fixed evidence set is `context.txt`, `tests.log`, `build.log`, `launch.log`, `steps.md`, `before.png`, `after.png`, and `state.json` inside that feature's `diagnostics/mac-ui` run directory.

## Baseline and HIG Target

- Existing baseline: `PracticeView` already implements the left/right drag shell, overlays, buttons, random draw, and navigation to `AnswerEditorView`; do not reimplement the completed `2026-08-05-practice-swipe-interaction.md` plan.
- Current HIG score: **6/10**. Native controls, SF Symbols, semantic colors, and basic touch targets are present, but the app is letterboxed, the practice file mixes too many states, the answer form is not keyboard-first, and VoiceOver/Reduce Motion/Dynamic Type acceptance is incomplete.
- Target HIG score: **10/10** after full-screen launch metadata, safe-area separation, adaptive single-card composition, equivalent gesture/button actions, accessible custom actions, Dynamic Type, Reduce Motion, meaningful threshold/result haptics, and device-level Computer Use proof.

## Computer Use Execution Contract

For each slug named below, set `FEATURE_SLUG` to that exact slug and execute this shell sequence. Replace the sample focused-test selector and default launch flags only when the task specifies different values:

```bash
export INTERVIEW_XCODE_DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer
export IF_SIMULATOR_UDID=779ACF98-BD23-4880-9F03-8DB9B9E43768
FEATURE_SLUG=iphone17-fullscreen
scripts/dev/preflight.sh
scripts/acceptance/start-run.sh "$FEATURE_SLUG"
IF_TEST_LOG_PATH="diagnostics/mac-ui/$FEATURE_SLUG/tests.log" \
  scripts/dev/test.sh -only-testing:InterviewFlashcardTests/PracticeSessionStateTests
IF_BUILD_LOG_PATH="diagnostics/mac-ui/$FEATURE_SLUG/build.log" \
IF_LAUNCH_LOG_PATH="diagnostics/mac-ui/$FEATURE_SLUG/launch.log" \
  scripts/dev/build-and-launch.sh \
    --ai stub --stub-mode success --speech unsupported \
    --fixture mvp-workflow --random-seed 7
scripts/acceptance/read-state.sh "$FEATURE_SLUG"
scripts/acceptance/finish-run.sh "$FEATURE_SLUG"
```

Before `read-state.sh`, operate Xcode Device Hub only through Computer Use, call `sky.get_app_state({ app: "com.apple.dt.Devices" })` before every action, and create `before.png` and `after.png` with `Cmd+Shift+3` plus `collect-screenshot.sh`. Update the generated `steps.md` using `apply_patch`, including the real path, visible result, independent state comparison, exceptions, and `Acceptance result: PASS`. A task-specific test command in the task replaces the sample `PracticeSessionStateTests` selector; a task-specific failure mode replaces `success` only for that failure run.

## File Map

- Modify `project.yml`: make the app iPhone-only and generate modern launch/scene/orientation metadata.
- Create `scripts/acceptance/assert-iphone-app-metadata.sh`: fail closed when the compiled app can enter compatibility mode.
- Modify `scripts/dev/build-and-launch.sh`: assert app metadata before installation.
- Modify `scripts/acceptance/run-final-checks.sh`: syntax-check the new script and require the new UI evidence slugs.
- Modify `docs/acceptance/computer-use-runbook.md`: record the full-screen, safe-area, Dynamic Type, Reduce Motion, and per-feature acceptance contracts.
- Create `InterviewFlashcard/Features/Practice/PracticeSessionState.swift`: pure finite-session state and summary.
- Create `InterviewFlashcardTests/PracticeSessionStateTests.swift`: state-transition and invariant tests.
- Create `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift`: shared stable identifiers.
- Create `InterviewFlashcard/Features/Practice/PracticeScopeView.swift`: Topic, practiced-card, and 5/10/20 session selection.
- Create `InterviewFlashcard/Features/Practice/PracticeSessionView.swift`: session header, current card, actions, and undo surface.
- Create `InterviewFlashcard/Features/Practice/QuestionCardView.swift`: safe-area-aware question presentation.
- Create `InterviewFlashcard/Features/Practice/PracticeSwipeActionLayer.swift`: drag visuals, threshold haptic, accessible alternatives, and Reduce Motion policy.
- Modify `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift`: use the researched 0.38 width threshold and expose threshold-crossing logic.
- Modify `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift`: cover the revised threshold and horizontal-intent invariants.
- Modify `InterviewFlashcard/Features/Practice/PracticeView.swift`: reduce to flow coordination, pure random drawing, navigation, and session transitions.
- Create `InterviewFlashcard/Features/Practice/AnswerComposerView.swift`: adaptive text/local-voice composer.
- Modify `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`: coordinate compose, processing, retry, result, and parent callbacks.
- Modify `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`: forward the already-persisted attempt through the shared callback exactly once.
- Create `InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift`: decode persisted result JSON into deterministic display rows.
- Create `InterviewFlashcardTests/EvaluationPresentationTests.swift`: JSON/result ordering tests.
- Create `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`: layered score, feedback, polish, reference answer, and history UI.
- Create `InterviewFlashcard/Features/Practice/PracticeSessionCompleteView.swift`: finite-session summary and next actions.
- Modify `InterviewFlashcardTests/EndToEndWorkflowTests.swift`: assert skip/back/submit/result invariants across the existing persistence pipeline.

---

### Task 1: Eliminate iPhone 17 Pro Max compatibility mode

**Files:**
- Modify: `project.yml`
- Create: `scripts/acceptance/assert-iphone-app-metadata.sh`
- Modify: `scripts/dev/build-and-launch.sh`
- Modify: `scripts/acceptance/run-final-checks.sh`
- Modify: `docs/acceptance/computer-use-runbook.md`

**Interfaces:**
- Input: path to a built `InterviewFlashcard.app`.
- Output: exit 0 only when the compiled `Info.plist` has generated launch/scene dictionaries, iPhone-only device family, and portrait orientation.
- Computer Use slug: `iphone17-fullscreen`.

- [ ] **Step 1: Create the failing compiled-metadata assertion**

Create `scripts/acceptance/assert-iphone-app-metadata.sh` with this contract:

```bash
#!/usr/bin/env bash

set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: $0 <InterviewFlashcard.app>" >&2; exit 2; }
readonly APP_PATH="$1"
readonly PLIST_PATH="$APP_PATH/Info.plist"
readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() { echo "FAILED: $*" >&2; exit 1; }
[[ -d "$APP_PATH" ]] || fail "app bundle missing: $APP_PATH"
[[ -f "$PLIST_PATH" ]] || fail "Info.plist missing: $PLIST_PATH"

"$PLIST_BUDDY" -c 'Print :UILaunchScreen' "$PLIST_PATH" >/dev/null \
  || fail "UILaunchScreen is missing"
"$PLIST_BUDDY" -c 'Print :UIApplicationSceneManifest' "$PLIST_PATH" >/dev/null \
  || fail "UIApplicationSceneManifest is missing"
[[ "$("$PLIST_BUDDY" -c 'Print :UIDeviceFamily:0' "$PLIST_PATH")" == "1" ]] \
  || fail "UIDeviceFamily[0] must be iPhone"
if "$PLIST_BUDDY" -c 'Print :UIDeviceFamily:1' "$PLIST_PATH" >/dev/null 2>&1; then
  fail "application target must not include iPad"
fi
[[ "$("$PLIST_BUDDY" -c 'Print :UISupportedInterfaceOrientations~iphone:0' "$PLIST_PATH")" == "UIInterfaceOrientationPortrait" ]] \
  || fail "the first supported iPhone orientation must be portrait"

echo "PASS: iPhone launch metadata prevents compatibility mode"
```

- [ ] **Step 2: Run it against the current product and record the red result**

```bash
export INTERVIEW_XCODE_DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer
export IF_SIMULATOR_UDID=779ACF98-BD23-4880-9F03-8DB9B9E43768
scripts/dev/preflight.sh
IF_BUILD_LOG_PATH=.build/logs/iphone17-metadata-red-build.log \
IF_LAUNCH_LOG_PATH=.build/logs/iphone17-metadata-red-launch.log \
scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported --fixture mvp-workflow
scripts/acceptance/assert-iphone-app-metadata.sh \
  .build/DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app
```

Expected: the assertion exits 1 with `UILaunchScreen is missing`; `plutil -p` also shows `UIDeviceFamily` contains both 1 and 2.

- [ ] **Step 3: Fix the application target metadata in `project.yml`**

Add these keys under `targets.InterviewFlashcard.settings.base`, even though a project-level device family exists:

```yaml
        TARGETED_DEVICE_FAMILY: "1"
        INFOPLIST_KEY_UILaunchScreen_Generation: "YES"
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation: "YES"
        INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone: "UIInterfaceOrientationPortrait"
```

Do not add a fixed launch storyboard, iPad family, landscape-only mode, or `UIRequiresFullScreen` workaround.

- [ ] **Step 4: Make every install fail closed on metadata regression**

In `scripts/dev/build-and-launch.sh`, immediately after the existing `APP_PATH` existence check, call:

```bash
"$REPOSITORY_ROOT/scripts/acceptance/assert-iphone-app-metadata.sh" "$APP_PATH"
```

Add the new script to the `bash -n` list in `scripts/acceptance/run-final-checks.sh`. Extend the runbook with two separate rules: the background fills the device window edge-to-edge, and all interactive content stays inside safe areas.

- [ ] **Step 5: Regenerate, rebuild, and verify compiled metadata**

```bash
xcodegen generate
IF_BUILD_LOG_PATH=.build/logs/iphone17-metadata-green-build.log \
IF_LAUNCH_LOG_PATH=.build/logs/iphone17-metadata-green-launch.log \
scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported --fixture mvp-workflow
scripts/acceptance/assert-iphone-app-metadata.sh \
  .build/DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app
```

Expected: build output contains `BUILD SUCCEEDED`, the metadata script prints `PASS`, and no application-target build setting resolves to `TARGETED_DEVICE_FAMILY = 1,2`.

- [ ] **Step 6: Verify the actual viewport through Computer Use**

Run the standard acceptance workflow for `iphone17-fullscreen`. In Xcode Device Hub, use Computer Use to foreground the freshly installed app, visit 练习 and 设置, and capture before/after desktop screenshots. Also save a supplemental device screenshot:

```bash
DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" \
  xcrun simctl io "$IF_SIMULATOR_UDID" screenshot \
  diagnostics/mac-ui/iphone17-fullscreen/viewport.png
sips -g pixelWidth -g pixelHeight \
  diagnostics/mac-ui/iphone17-fullscreen/viewport.png
```

Expected: `pixelWidth: 1320`, `pixelHeight: 2868`; there are no letterbox bands above or below the app surface; background continues beneath status/home-indicator areas; tab controls, navigation content, and buttons remain unobscured.

- [ ] **Step 7: Commit only the full-screen contract**

```bash
git add project.yml \
  scripts/acceptance/assert-iphone-app-metadata.sh \
  scripts/dev/build-and-launch.sh \
  scripts/acceptance/run-final-checks.sh \
  docs/acceptance/computer-use-runbook.md
git commit -m "fix: fill iPhone 17 Pro Max viewport"
```

---

### Task 2: Add a pure finite-session state machine

**Files:**
- Create: `InterviewFlashcard/Features/Practice/PracticeSessionState.swift`
- Create: `InterviewFlashcardTests/PracticeSessionStateTests.swift`

**Interfaces:**

```swift
enum PracticeSessionSize: Int, CaseIterable, Identifiable, Sendable {
    case five = 5
    case ten = 10
    case twenty = 20
    var id: Int { rawValue }
    var title: String { "\(rawValue) 题" }
}

enum PracticeSessionEndReason: Equatable, Sendable {
    case targetReached
    case poolExhausted
}

struct PracticeSessionSummary: Equatable, Sendable {
    let targetCount: Int
    let completedCount: Int
    let answeredCount: Int
    let skippedCount: Int
    let elapsed: TimeInterval
    let endReason: PracticeSessionEndReason?
}

struct PracticeSessionState: Equatable, Sendable {
    let targetCount: Int
    let startedAt: Date
    private(set) var completedCount: Int
    private(set) var answeredCount: Int
    private(set) var skippedCount: Int
    private(set) var currentQuestionID: UUID?
    private(set) var undoQuestionID: UUID?
    private(set) var endReason: PracticeSessionEndReason?

    init(size: PracticeSessionSize, startedAt: Date)
    mutating func present(_ questionID: UUID)
    mutating func skipCurrent() -> UUID?
    mutating func answerSubmitted(questionID: UUID) -> Bool
    mutating func undoLastSkip() -> UUID?
    mutating func expireUndo()
    mutating func finishBecausePoolIsExhausted()
    func summary(at now: Date) -> PracticeSessionSummary
    var isComplete: Bool { get }
}
```

- [ ] **Step 1: Write state-transition tests first**

Cover these exact invariants in `PracticeSessionStateTests`:

```swift
func testSkipCountsCompletionWithoutCreatingAnAnswerState()
func testUndoRestoresExactSkippedQuestionAndCounters()
func testStartingAnswerWithoutSubmissionDoesNotAdvance()
func testSubmittedAnswerAdvancesExactlyOnce()
func testTargetCountEndsSession()
func testPoolExhaustionEndsShortSession()
func testSummaryUsesInjectedDatesForElapsedTime()
```

The first test must assert `completedCount == 1`, `skippedCount == 1`, and `answeredCount == 0`. The idempotence test must call `answerSubmitted(questionID:)` twice and assert the second result is `false`.

- [ ] **Step 2: Run the focused test and verify red**

```bash
IF_TEST_LOG_PATH=.build/logs/practice-session-state-red.log \
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/PracticeSessionStateTests
```

Expected: compile failure because `PracticeSessionState` does not exist.

- [ ] **Step 3: Implement the minimal value type**

Implement all transitions without SwiftData, timers, views, or global clocks. `skipCurrent()` increments completed/skipped, stores only the last skipped ID, clears current, and sets `.targetReached` at the target. `undoLastSkip()` restores the ID, decrements both counters, clears the end reason, and consumes the undo token. `answerSubmitted` requires the current ID, increments completed/answered, clears undo, and is idempotent.

- [ ] **Step 4: Run focused and related random-draw tests**

```bash
IF_TEST_LOG_PATH=.build/logs/practice-session-state-green.log \
scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSessionStateTests \
  -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests
```

Expected: `TEST SUCCEEDED`; `QuestionDrawService` remains pure random and its default practiced-card filtering is unchanged.

- [ ] **Step 5: Commit the state machine**

```bash
git add InterviewFlashcard/Features/Practice/PracticeSessionState.swift \
  InterviewFlashcardTests/PracticeSessionStateTests.swift
git commit -m "feat: add finite practice session state"
```

---

### Task 3: Split practice scope and adaptive single-card session UI

**Files:**
- Create: `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift`
- Create: `InterviewFlashcard/Features/Practice/PracticeScopeView.swift`
- Create: `InterviewFlashcard/Features/Practice/PracticeSessionView.swift`
- Create: `InterviewFlashcard/Features/Practice/QuestionCardView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`

**Interfaces:**

```swift
struct PracticeTopicOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let activeCardCount: Int
}

struct PracticeScopeSelection: Equatable, Sendable {
    var selectedTopicIDs: Set<UUID>
    var includePracticed = false
    var sessionSize: PracticeSessionSize = .ten
}

struct PracticeScopeView: View {
    let topics: [PracticeTopicOption]
    @Binding var selection: PracticeScopeSelection
    let onStart: () -> Void
}

struct PracticeSessionView: View {
    let card: QuestionCardSnapshot
    let summary: PracticeSessionSummary
    let canUndo: Bool
    let onSkip: () -> Void
    let onStartAnswer: () -> Void
    let onUndo: () -> Void
    let onChangeScope: () -> Void
}

struct QuestionCardView: View {
    let card: QuestionCardSnapshot
    let progressText: String
}
```

- [ ] **Step 1: Move stable accessibility identifiers out of `PracticeView`**

Create `PracticeAccessibilityID.swift` with identifiers for scope, count picker, practiced toggle, start, session, progress, card, question, skip, answer, undo, change scope, and completion. Preserve existing identifier strings where they already exist so current acceptance scripts do not break.

- [ ] **Step 2: Build the scope view with default 10-question selection**

Use a `Form` with Topic toggles, the default-off practiced toggle, and a segmented `Picker` over `PracticeSessionSize.allCases`. Disable start when no Topic is selected or the selected scope has zero eligible cards. Keep the current “全选/清空” behavior and active-card counts.

- [ ] **Step 3: Build the adaptive question card**

Use this safe-area pattern in `PracticeSessionView`:

```swift
ZStack {
    Color(uiColor: .systemGroupedBackground)
        .ignoresSafeArea()

    VStack(spacing: 16) {
        sessionHeader
        QuestionCardView(card: card, progressText: progressText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        actionButtons
    }
    .safeAreaPadding(.horizontal, 20)
    .safeAreaPadding(.bottom, 12)
}
```

Inside `QuestionCardView`, make Topic secondary, question the only high-emphasis text, and long questions vertically scrollable. Use Dynamic Type styles and no fixed card height or screen measurement.

- [ ] **Step 4: Reduce `PracticeView` to coordination**

Replace `.filters/.card/.empty` with a flow enum that includes `.scope`, `.session`, and `.complete`. `PracticeView` owns `PracticeScopeSelection`, `PracticeSessionState`, current snapshot, seeded generator, and answer destination. Starting creates a new transient state at `environment.dependencies.now()`, draws randomly, and calls `present`. When no eligible card exists, set `.poolExhausted` and transition to completion instead of an infinite empty loop.

- [ ] **Step 5: Build and run focused regression tests**

```bash
IF_TEST_LOG_PATH=.build/logs/practice-session-layout-tests.log \
scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSessionStateTests \
  -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests \
  -only-testing:InterviewFlashcardTests/AppShellTests
```

Expected: `TEST SUCCEEDED`; root tabs are unchanged and the session defaults to 10 with practiced cards excluded.

- [ ] **Step 6: Computer Use acceptance on iPhone 17 Pro Max**

Run slug `practice-session-layout` with fixture `mvp-workflow` and seed `7`. Through Device Hub, select all Topics, leave “包含已练习题” off, select 10, start, scroll a long question, and use both visible action buttons without completing an answer. Pass only when one card fills the available safe-area height, progress reads `1/10`, no full-score answer appears, and no top/bottom letterbox exists. `state.json` must show no new attempt from entering or leaving the session.

- [ ] **Step 7: Commit the adaptive practice split**

```bash
git add InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift \
  InterviewFlashcard/Features/Practice/PracticeScopeView.swift \
  InterviewFlashcard/Features/Practice/PracticeSessionView.swift \
  InterviewFlashcard/Features/Practice/QuestionCardView.swift \
  InterviewFlashcard/Features/Practice/PracticeView.swift
git commit -m "refactor: split adaptive practice session UI"
```

---

### Task 4: Add swipe feedback, undo, haptics, and accessibility

**Files:**
- Create: `InterviewFlashcard/Features/Practice/PracticeSwipeActionLayer.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeSessionView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift`
- Modify: `InterviewFlashcardTests/PracticeSessionStateTests.swift`

**Interfaces:**

```swift
struct PracticeSwipeActionLayer<Content: View>: View {
    let cardWidth: CGFloat
    let isInteractionDisabled: Bool
    let onCommit: (PracticeSwipeAction) -> Void
    let content: Content

    init(
        cardWidth: CGFloat,
        isInteractionDisabled: Bool,
        onCommit: @escaping (PracticeSwipeAction) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cardWidth = cardWidth
        self.isInteractionDisabled = isInteractionDisabled
        self.onCommit = onCommit
        self.content = content()
    }
}

extension PracticeSwipeInteraction {
    static let distanceThresholdRatio: CGFloat = 0.38
    static func crossedDistanceThreshold(
        previousWidth: CGFloat,
        currentWidth: CGFloat,
        cardWidth: CGFloat
    ) -> Bool
}
```

- [ ] **Step 1: Update failing threshold and crossing tests**

Change threshold fixtures so 113 points on a 300-point card does not commit and 115 points does. Add tests that crossing fires only when moving from below to at/above the threshold, never for vertical intent, and never repeatedly while remaining beyond the threshold.

- [ ] **Step 2: Implement continuous preview and discrete commit**

Move drag translation, overlay opacity, rotation, exit animation, and gesture handling from `PracticeView` into `PracticeSwipeActionLayer`. A release below threshold springs back and performs no business action. A release above threshold calls the same closure as its matching visible button after the exit animation.

- [ ] **Step 3: Add one threshold haptic and Reduce Motion behavior**

Use `@Environment(\.accessibilityReduceMotion)` and a per-gesture threshold token. With motion allowed, use at most 7 degrees rotation and a 0.22-second exit. With Reduce Motion, use no rotation and a short opacity/translation transition. Attach `.sensoryFeedback(.selection, trigger:)` only to the first threshold crossing and success/error feedback only to answer-processing completion/failure.

- [ ] **Step 4: Add the three-second single-step undo**

After skip, draw the next random card and show a bottom toast `已跳过 · 撤回` for three seconds. Keep one cancellable `Task`; a new skip replaces the prior undo, starting an answer expires it, and tapping undo restores the exact prior question and decrements session progress. Undo creates no attempt and must work even when the skip temporarily reached `SessionComplete`.

- [ ] **Step 5: Add non-gesture accessibility paths**

Keep both visible buttons at least 44 × 44 pt. Add card custom actions named “跳过” and “开始回答”. Accessibility reading order must be Topic → question → progress → skip → start answer. Mark drag overlays hidden from accessibility. Use text labels plus symbols so color is never the only direction cue.

- [ ] **Step 6: Run focused tests**

```bash
IF_TEST_LOG_PATH=.build/logs/practice-swipe-accessibility-tests.log \
scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests \
  -only-testing:InterviewFlashcardTests/PracticeSessionStateTests
```

Expected: `TEST SUCCEEDED`; skip/undo counters are exact and threshold intent remains horizontal.

- [ ] **Step 7: Computer Use acceptance for gesture, undo, and accessibility**

Run slug `practice-undo-accessibility`. Use a real drag below threshold and verify return; drag left above threshold and immediately tap 撤回; verify the exact question and `1/10` return. Repeat skip and start-answer through visible buttons. In Simulator Settings, enable Reduce Motion and an Accessibility Extra Large text size through Computer Use, relaunch, and repeat the path; then restore both settings. Pass only when content remains readable without clipped primary controls, motion is reduced, gesture/button behavior matches, and `state.json` attempt count remains unchanged until submission.

- [ ] **Step 8: Commit interaction and accessibility behavior**

```bash
git add InterviewFlashcard/Features/Practice/PracticeSwipeActionLayer.swift \
  InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift \
  InterviewFlashcard/Features/Practice/PracticeSessionView.swift \
  InterviewFlashcard/Features/Practice/PracticeView.swift \
  InterviewFlashcardTests/PracticeSwipeInteractionTests.swift \
  InterviewFlashcardTests/PracticeSessionStateTests.swift
git commit -m "feat: add recoverable accessible practice swipes"
```

---

### Task 5: Refactor answering into a full-height keyboard-safe composer

**Files:**
- Create: `InterviewFlashcard/Features/Practice/AnswerComposerView.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Modify: `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcardTests/AnswerSubmissionServiceTests.swift`
- Modify: `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`

**Interfaces:**

```swift
struct AnswerComposerView: View {
    let questionText: String
    @Binding var answerText: String
    let isProcessing: Bool
    let localSpeechCapability: LocalSpeechCapability
    let onSubmitText: () -> Void
    let onStartVoice: () -> Void
}

@MainActor
struct AnswerEditorView: View {
    init(
        questionID: UUID,
        onAttemptSubmitted: @escaping (UUID) -> Void = { _ in },
        onContinueSession: @escaping () -> Void = {}
    )
}
```

- [ ] **Step 1: Add callback invariants to submission tests**

Extend text and voice tests to assert the returned attempt is already saved before the UI callback can run. Preserve raw text, input mode, question snapshot, reference-answer snapshot, and local audio metadata. No callback occurs for empty text, cancelled voice, transcription failure, or navigation back.

- [ ] **Step 2: Extract the answer composer**

Replace the dense `Form` input section with an adaptive `ScrollView`. Show question, a short “先回答，提交后再看评分与满分答案” note, and a large `TextEditor`. Put the submit button in `.safeAreaInset(edge: .bottom)` so it remains above the keyboard and home indicator. Use only Dynamic Type styles and a flexible editor; do not set screen-height frames.

- [ ] **Step 3: Enforce the local speech boundary in UI**

When `localSpeechCapability.canStartVoiceAnswer` is true, show “录音并本地转写”. Otherwise show a noninteractive `Label("本机无法本地转写", systemImage: "mic.slash")` and the existing concise explanation. Never open `VoiceAnswerView` when capability is false.

- [ ] **Step 4: Wire answer persistence to session progress exactly once**

After `AnswerSubmissionService.submitText` returns, call `onAttemptSubmitted(card.id)` once, then start processing. In the voice sheet, call the same closure from `VoiceAnswerView.onSubmitted` after persistence and before processing. The parent calls `session.answerSubmitted(questionID:)`, prepares the next random card behind the navigation destination, and does not increment again on retry or result rendering.

- [ ] **Step 5: Run focused text and voice tests**

```bash
IF_TEST_LOG_PATH=.build/logs/answer-composer-tests.log \
scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/AnswerSubmissionServiceTests \
  -only-testing:InterviewFlashcardTests/VoiceAnswerFlowTests \
  -only-testing:InterviewFlashcardTests/SpeechCapabilityTests
```

Expected: `TEST SUCCEEDED`; unavailable local transcription fails closed and text submission still persists before processing.

- [ ] **Step 6: Computer Use acceptance with the real keyboard**

Run slug `answer-composer-iphone17` with deterministic AI success and unsupported speech. Right-swipe to answer, focus the text editor, type a representative multiline answer, scroll while the keyboard is visible, and submit. Pass only when the editor and submit button are usable above the keyboard, no full-score answer is visible before submission, the voice control is noninteractive, and `state.json` changes from zero attempts to one persisted raw attempt. Back out without submitting a second question and verify progress does not advance.

- [ ] **Step 7: Commit the answer composer**

```bash
git add InterviewFlashcard/Features/Practice/AnswerComposerView.swift \
  InterviewFlashcard/Features/Practice/AnswerEditorView.swift \
  InterviewFlashcard/Features/Practice/VoiceAnswerView.swift \
  InterviewFlashcard/Features/Practice/PracticeView.swift \
  InterviewFlashcardTests/AnswerSubmissionServiceTests.swift \
  InterviewFlashcardTests/VoiceAnswerFlowTests.swift
git commit -m "refactor: add keyboard-safe answer composer"
```

---

### Task 6: Build a layered AI evaluation result

**Files:**
- Create: `InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift`
- Create: `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`
- Create: `InterviewFlashcardTests/EvaluationPresentationTests.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`

**Interfaces:**

```swift
struct EvaluationDimensionRow: Equatable, Sendable {
    let dimension: ScoreDimension
    let score: Int
    let feedback: String?
}

struct EvaluationPresentation: Equatable, Sendable {
    let totalScore: Int?
    let dimensions: [EvaluationDimensionRow]
    let strengths: [String]
    let improvements: [String]
    let rawText: String
    let polishedText: String?
    let referenceAnswer: String
    let referenceVersion: Int

    init(evaluation: EvaluationRecord)
}

struct EvaluationResultView: View {
    let evaluation: EvaluationRecord
    let onContinue: () -> Void
}
```

- Computer Use slugs: `answer-result-success` and `answer-result-failure`.

- [ ] **Step 1: Write presentation-decoding tests**

Test valid and malformed `strengthsJSON`, `nextAnswerPlanJSON`, and `feedbackJSON`. Valid feedback must map by `ScoreDimension.rawValue`; malformed JSON must produce empty collections rather than crash. Assert rows always follow `ScoreDimension.allCases` order: correctness, coverage, reasoning, structure, tradeoffs, precision.

- [ ] **Step 2: Run the focused test and verify red**

```bash
IF_TEST_LOG_PATH=.build/logs/evaluation-presentation-red.log \
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/EvaluationPresentationTests
```

Expected: compile failure because `EvaluationPresentation` does not exist.

- [ ] **Step 3: Implement the presentation adapter without schema changes**

Read scores from `EvaluationRecord.dimensionScores`, feedback from its persisted dictionary, strengths/improvements from their persisted arrays, raw/reference text from `evaluation.attempt`, and polished text from the highest-revision `PolishResultRecord`. Use the immutable reference-answer snapshot, not the question's current reference version.

- [ ] **Step 4: Implement the layered result view**

Order content as: processing/result status → total score → six expandable dimension rows with feedback → strengths and next-answer plan → raw versus polished answer → full-score answer and version → link to `QuestionHistoryView(question: evaluation.attempt.question)` → primary “下一题” or “完成本组” action. The full-score answer appears only in this result state. Use text and shape, not red/green alone, to communicate scores.

- [ ] **Step 5: Replace the inline result section in `AnswerEditorView`**

Keep the processing spinner, failure message, and retry button in the editor coordinator. When `processingResult` becomes non-nil, show `EvaluationResultView`. Retry must reuse the saved attempt and never call `onAttemptSubmitted` again.

- [ ] **Step 6: Run presentation and processing tests**

```bash
IF_TEST_LOG_PATH=.build/logs/evaluation-result-tests.log \
scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/EvaluationPresentationTests \
  -only-testing:InterviewFlashcardTests/AnswerProcessingServiceTests \
  -only-testing:InterviewFlashcardTests/AIResponseValidatorTests \
  -only-testing:InterviewFlashcardTests/HistoryQueryTests
```

Expected: `TEST SUCCEEDED`; malformed display JSON cannot crash the result, and scoring still uses the polished text while retaining raw text.

- [ ] **Step 7: Computer Use acceptance of success and failure results**

Run `answer-result-success` with `--stub-mode success` and `answer-result-failure` with `--stub-mode evaluation-invalid`. For success, verify processing → total → six scores → feedback → polished answer → full-score answer → history. For failure, verify raw answer remains in history, retry is visible, and no zero score is fabricated. Each slug's `state.json` must agree with the visible attempt, polish, evaluation, and status.

- [ ] **Step 8: Commit the result hierarchy**

```bash
git add InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift \
  InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift \
  InterviewFlashcardTests/EvaluationPresentationTests.swift \
  InterviewFlashcard/Features/Practice/AnswerEditorView.swift
git commit -m "feat: add layered interview evaluation result"
```

---

### Task 7: Add explicit finite-session completion

**Files:**
- Create: `InterviewFlashcard/Features/Practice/PracticeSessionCompleteView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcardTests/PracticeSessionStateTests.swift`

**Interfaces:**

```swift
struct PracticeSessionCompleteView: View {
    let summary: PracticeSessionSummary
    let onRestartSameScope: () -> Void
    let onChangeScope: () -> Void
}
```

- [ ] **Step 1: Add completion-boundary tests**

Assert a 5-question session reaches completion after any five answered/skipped decisions, undo reopens a just-completed session, pool exhaustion records a distinct reason, restart creates fresh zero counters, and the prior summary value remains immutable.

- [ ] **Step 2: Implement the completion screen**

Show a calm completion symbol, `已完成 n 题`, answered count, skipped count, elapsed minutes/seconds, and an early-end explanation when the eligible pool is exhausted. Provide “再来一组” and “调整范围”. Do not auto-draw or auto-start another session and do not add confetti, streaks, random rewards, or notifications.

- [ ] **Step 3: Wire restart and scope change**

“再来一组” keeps selected Topics, practiced-card option, and session size but creates a fresh state and random draw. “调整范围” returns to `PracticeScopeView`; its practiced toggle remains default-off only when a wholly new scope selection is created, not when navigating back inside the same session setup.

- [ ] **Step 4: Run session and end-to-end tests**

```bash
IF_TEST_LOG_PATH=.build/logs/practice-session-complete-tests.log \
scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/PracticeSessionStateTests \
  -only-testing:InterviewFlashcardTests/EndToEndWorkflowTests
```

Expected: `TEST SUCCEEDED`; no extra attempt or random draw is created after completion.

- [ ] **Step 5: Computer Use acceptance of both end reasons**

Run slug `practice-session-complete` with a deterministic 5-question scope. Complete it using a mix of submissions and skips, verify the counts and elapsed value, tap “再来一组”, then finish a separate small eligible pool early. Pass only when no card loads automatically after completion and visible counts match attempts in `state.json` plus the recorded skipped decisions in `steps.md`.

- [ ] **Step 6: Commit session completion**

```bash
git add InterviewFlashcard/Features/Practice/PracticeSessionCompleteView.swift \
  InterviewFlashcard/Features/Practice/PracticeView.swift \
  InterviewFlashcardTests/PracticeSessionStateTests.swift
git commit -m "feat: add finite practice completion state"
```

---

### Task 8: Lock the end-to-end contract and collect final device evidence

**Files:**
- Modify: `InterviewFlashcardTests/EndToEndWorkflowTests.swift`
- Modify: `scripts/acceptance/run-final-checks.sh`
- Modify: `docs/acceptance/computer-use-runbook.md`

**Interfaces:**
- Required slugs: `iphone17-fullscreen`, `practice-session-layout`, `practice-undo-accessibility`, `answer-composer-iphone17`, `answer-result-success`, `answer-result-failure`, `practice-session-complete`.
- Required evidence per slug: the eight fixed artifacts defined in Global Constraints.

- [ ] **Step 1: Extend end-to-end invariants**

Use the existing in-memory container and deterministic AI client to assert: skip produces no attempt; right-navigation/back produces no attempt; text submit saves raw input before polish; completed evaluation has six scores; reference answer remains the submitted snapshot; retry does not create a second attempt; and a submitted question increments session progress exactly once.

- [ ] **Step 2: Require all redesign evidence in final checks**

Append the seven slugs above to `required_features` in `scripts/acceptance/run-final-checks.sh`. Add runbook rows with the exact path, visible result, and independent `state.json` assertion for each slug.

- [ ] **Step 3: Run the complete automated suite**

```bash
export INTERVIEW_XCODE_DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer
export IF_SIMULATOR_UDID=779ACF98-BD23-4880-9F03-8DB9B9E43768
scripts/dev/preflight.sh
IF_TEST_LOG_PATH=.build/logs/iphone17-redesign-all-tests.log scripts/dev/test.sh
```

Expected: `TEST SUCCEEDED` with no compile warnings introduced by this refactor.

- [ ] **Step 4: Build and launch the exact checkout used for acceptance**

```bash
IF_BUILD_LOG_PATH=.build/logs/iphone17-redesign-final-build.log \
IF_LAUNCH_LOG_PATH=.build/logs/iphone17-redesign-final-launch.log \
scripts/dev/build-and-launch.sh \
  --ai stub --stub-mode success --speech unsupported \
  --fixture mvp-workflow --random-seed 7
```

Expected: metadata assertion passes, output contains `BUILD SUCCEEDED`, the current commit is installed, and launch output identifies `com.gaoguobin.InterviewFlashcard`.

- [ ] **Step 5: Complete all seven Computer Use runs**

For each slug, call `scripts/acceptance/start-run.sh`, save focused/full tests to `tests.log`, build and launch with slug-specific log paths, interact only through Computer Use in `com.apple.dt.Devices`, capture before/after with `Cmd+Shift+3`, run `scripts/acceptance/read-state.sh`, document exact actions/results, mark PASS, and call `scripts/acceptance/finish-run.sh`. Do not reuse screenshots or state from another commit or slug.

- [ ] **Step 6: Perform the 10/10 HIG review**

Record a pass/fail table in the runbook for: full device fill; Dynamic Island/home-indicator safety; Dynamic Type at Accessibility Extra Large; 44 × 44 targets; VoiceOver custom actions and reading order; Voice Control button names; Reduce Motion; color-independent cues; keyboard avoidance; semantic Dark/Light appearance; and no reference answer before submission. Any failed row blocks signoff.

- [ ] **Step 7: Run final checks and inspect scope**

```bash
scripts/acceptance/run-final-checks.sh
git status --short
git diff --check
git diff --stat
```

Expected: final checks print `PASS`, no placeholder markers exist in new source, no generated `.xcodeproj` files are unignored, and unrelated dirty-worktree files are not staged.

- [ ] **Step 8: Commit final regression and acceptance contracts**

```bash
git add InterviewFlashcardTests/EndToEndWorkflowTests.swift \
  scripts/acceptance/run-final-checks.sh \
  docs/acceptance/computer-use-runbook.md
git commit -m "test: lock iPhone practice redesign acceptance"
```

## Final Acceptance Matrix

| Contract | Automated proof | Computer Use proof | Pass condition |
| --- | --- | --- | --- |
| Full-screen iPhone 17 Pro Max | Compiled plist assertion | `iphone17-fullscreen` | 1320 × 2868 device image, no letterbox, safe controls |
| Scope and finite session | Session/draw tests | `practice-session-layout` | Default 10, optional 5/20, practiced off, one card |
| Swipe semantics | Swipe/state tests | `practice-undo-accessibility` | Left skips, right answers, below threshold returns |
| Recoverability | Undo counter tests | `practice-undo-accessibility` | Exact card and progress restored within three seconds |
| Answer boundary | Submission/voice tests | `answer-composer-iphone17` | Back creates nothing; submit persists raw attempt once |
| AI result hierarchy | Presentation/processing tests | `answer-result-success`, `answer-result-failure` | Six scores/feedback on success; retained raw attempt and no fake zero on failure |
| Session stopping point | Completion tests | `practice-session-complete` | Explicit summary; no infinite automatic continuation |
| Accessibility/HIG | Policy and state tests | all UI slugs | Dynamic Type, VoiceOver, Voice Control, Reduce Motion pass |

## Out of Scope

- Persisting or syncing practice sessions.
- Weak-topic recommendation, automatic review scheduling, FSRS, or changing pure-random draw.
- New AI prompts, scoring dimensions, DeepSeek transport, or SwiftData migrations.
- Persisting per-dimension evidence quotes not already present in `EvaluationRecord`.
- Card-stack previews, social/profile visuals, gamified streaks, variable rewards, notifications, or subscriptions.
- iPad, landscape, or any simulator/device other than the pinned iPhone 17 Pro Max.
