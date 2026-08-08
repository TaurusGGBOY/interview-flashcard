# Prompt 3 Product Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the Prompt 3 product improvements as one coherent local-first iOS workflow: a larger non-scrolling practice card, real DeepSeek-backed normal operation, inline local voice transcription, searchable history and question bank, and direct question answering from the library.

**Architecture:** Preserve the existing SwiftUI + SwiftData composition. Modify the composition root only for the default AI provider, keep search as in-memory filtering over existing SwiftData relationships, and reuse the current speech protocols and answer editor rather than adding new persistence models or navigation routes.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, SwiftData, XCTest, Apple Speech framework, AVFoundation, DeepSeek Chat Completions API, XcodeGen.

## Global Constraints

- Normal Debug and Release operation must use `DeepSeekAIClient`; Stub is available only through explicit provider configuration or tests.
- Missing or invalid API credentials must produce a visible error and must never silently create simulated AI results.
- Voice audio remains on device and is transcribed on device; transcription is appended to the current editor without navigation or confirmation.
- Search is local and must exclude trashed questions while preserving existing Topic filtering and newest-first history ordering.
- Preserve unrelated dirty worktree changes; only edit the files listed for each task and do not stage unrelated files.
- Keep existing accessibility identifiers stable and add identifiers for new search and inline voice controls.

## File Map

- `InterviewFlashcard/App/AppEnvironment.swift`: Change the Debug default dependency/provider policy and keep explicit Stub overrides.
- `InterviewFlashcard/Features/Settings/SettingsView.swift`: Make the active AI provider and missing-Key state visible to users.
- `InterviewFlashcard/Features/Practice/PracticeFeedView.swift`: Remove duplicate card label and allocate a larger touch area.
- `InterviewFlashcard/Features/Practice/QuestionCardView.swift`: Remove nested question scrolling and use adaptive wrapped text.
- `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`: Reuse the speech controller in an inline transcription control with immediate callback semantics.
- `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`: Host the inline voice control and append transcripts into the answer text.
- `InterviewFlashcard/Features/History/HistoryQuery.swift`: Provide a pure, testable search predicate for attempts.
- `InterviewFlashcard/Features/History/HistoryView.swift`: Add local history search while retaining Topic filtering and row navigation.
- `InterviewFlashcard/Features/Library/LibrarySearch.swift`: Provide pure question/Topic matching and result ordering for library search.
- `InterviewFlashcard/Features/Library/LibraryView.swift`: Add question-bank search results and direct navigation to question details.
- `InterviewFlashcard/Features/Library/QuestionDetailView.swift`: Add a direct “开始回答” navigation action.
- `InterviewFlashcardTests/AppShellTests.swift`: Lock the real-provider default and explicit Stub override.
- `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`: Verify immediate transcription completion and draft lifecycle.
- `InterviewFlashcardTests/HistoryQueryTests.swift`: Verify case-insensitive search over question, answer, and Topic fields.
- `InterviewFlashcardTests/LibrarySearchTests.swift`: Verify active-card filtering, matching fields, ordering, and trashed-card exclusion.
- `InterviewFlashcardTests/AnswerEditorTests.swift`: Verify transcript append separators and empty-text behavior.
- `InterviewFlashcardTests/PracticeCardLayoutTests.swift`: Verify the practice-card layout contract that can be expressed without a UI host.
- `project.yml` / generated Xcode project: Include any newly created Swift test/source files if XcodeGen does not update the checked-in project automatically.

---

### Task 1: Make normal AI operation real

**Files:**
- Modify: `InterviewFlashcard/App/AppEnvironment.swift` in `LaunchOptions.current` and `Dependencies.live`.
- Modify: `InterviewFlashcard/Features/Settings/SettingsView.swift` in the AI settings section.
- Test: `InterviewFlashcardTests/AppShellTests.swift`.

**Interfaces:**
- Consumes: existing `AppEnvironment.LaunchOptions.AIProvider`, `DeepSeekAIClient`, `KeychainAPIKeyStore`, and `AppRuntime` composition.
- Produces: a Debug default of `.deepseek`, explicit Stub selection through existing launch arguments/environment/UserDefaults, and user-visible provider status.

- [ ] **Step 1: Write the failing provider-default tests**

Add a test that constructs `LaunchOptions.current` with no provider argument, empty environment, and a clean isolated `UserDefaults` suite, then expects `.deepseek`. Keep the existing explicit `-IFAIProvider stub` test and add an assertion that it still produces `.stub` with its selected Stub mode.

- [ ] **Step 2: Run the focused test to verify the default assertion fails**

Run:

```bash
xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'generic/platform=iOS Simulator' -only-testing:InterviewFlashcardTests/AppShellTests
```

Expected: the new no-argument default test fails because Debug currently resolves to `.stub`.

- [ ] **Step 3: Switch the default without removing the test seam**

Make `.deepseek` the final Debug fallback after launch arguments, environment, and persisted settings. Keep `.stub` available only when explicitly selected. Make `Dependencies.live` construct a real DeepSeek client backed by Keychain so previews and default environments do not hide a simulated client. Keep `AppRuntime`’s persisted provider selection and key handoff unchanged. Add a concise settings status showing “当前 AI：DeepSeek” or “当前 AI：测试 Stub” and a direct explanation when the live provider has no Key.

- [ ] **Step 4: Run the focused tests to verify the provider behavior**

Run the same `xcodebuild test` command. Expected: both the default DeepSeek test and explicit Stub test pass, and no existing AppShell tests regress.

- [ ] **Step 5: Review the import runtime boundary**

Confirm by source inspection and the existing import tests that `ImportView` still calls `ImportCoordinator` with `environment.dependencies.aiClient`, and that no normal UI path invokes `AcceptanceSeeder`, `FixtureSpeechTranscriber`, or `StubAIClient` without an explicit override. Do not replace test fixtures with network calls.

### Task 2: Enlarge the practice card and remove nested scrolling

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/PracticeFeedView.swift` in `cardFeed`.
- Modify: `InterviewFlashcard/Features/Practice/QuestionCardView.swift` in the question-content layout.
- Test: `InterviewFlashcardTests/PracticeCardLayoutTests.swift` if a new pure layout contract is needed.

**Interfaces:**
- Consumes: existing `QuestionCardSnapshot`, `PracticeSwipeActionLayer`, and `PracticeAccessibilityID` values.
- Produces: the existing practice actions with the card occupying the available feed height, card label “随机”, and no inner vertical scroll view.

- [ ] **Step 1: Add a regression check for the text-layout contract**

Add a source-level or pure helper test for the chosen adaptive text policy: a long question must be allowed to wrap and the layout contract must not advertise an inner scroll container. Keep gesture behavior covered by the existing `PracticeSwipeInteractionTests`.

- [ ] **Step 2: Implement the larger feed layout**

Change the card header label from “随机练习” to “随机”. Give the `GeometryReader` a larger minimum height and flexible maximum height so it consumes remaining screen space. Keep horizontal safe-area padding modest, keep the action buttons at a minimum 48pt height, and ensure the undo button does not collapse the card below the intended minimum.

- [ ] **Step 3: Replace the question `ScrollView` with adaptive wrapped text**

Render the question directly inside the card’s flexible content area. Preserve text selection and accessibility. Use semantic fonts and an adaptive fallback (for example, `ViewThatFits` or a bounded minimum scale factor) so the common long sample question wraps within the card without requiring a vertical swipe. Do not alter the card’s horizontal swipe gesture layer.

- [ ] **Step 4: Run focused interaction and build checks**

Run:

```bash
xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'generic/platform=iOS Simulator' -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests -only-testing:InterviewFlashcardTests/PracticeCardLayoutTests
```

Expected: swipe threshold/action tests pass and the new layout contract passes. Build the core target if the UI test host cannot compile the SwiftUI view.

### Task 3: Convert voice input to inline immediate append

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`.
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`.
- Test: `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`.
- Test: `InterviewFlashcardTests/AnswerEditorTests.swift`.

**Interfaces:**
- Consumes: `SpeechTranscribing`, `AudioRecording`, `VoiceAnswerController`, `AppleSpeechTranscriber`, and `M4AAudioRecorder`.
- Produces: an inline voice control that calls `onTranscript(String)` after successful local transcription; `AnswerEditorView` exposes a pure transcript-append helper used by tests.

- [ ] **Step 1: Update controller tests for immediate completion**

Change the supported-flow test to expect a ready/idle recording state after `stopAndTranscribe()` returns its transcript, with the exact transcript text available to the callback path. Keep the permission failure and local-file cleanup tests. Add a test that a successful stop does not create an answer attempt or invoke scoring by itself.

- [ ] **Step 2: Run the focused voice tests to record the expected failures**

Run:

```bash
xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'generic/platform=iOS Simulator' -only-testing:InterviewFlashcardTests/VoiceAnswerFlowTests
```

Expected: the updated immediate-completion expectations fail against the current confirmation-page state machine.

- [ ] **Step 3: Refactor the controller/view seam**

Keep capability checking, recording, stopping, local transcription, error states, and cancellation in `VoiceAnswerController`. Make successful stop return or publish the normalized transcript and return to an idle/ready state. Replace the normal `VoiceAnswerView` sheet UI with an inline control that displays “开始录音”, “停止录音”, “正在本地转写…”, and local retry/error states. Do not show the old confirmation editor or navigate to another page.

- [ ] **Step 4: Append the transcript in the answer editor**

Add a pure `AnswerEditorView.appendTranscript(current:transcript:)` helper. It must trim an empty transcript to no-op, append a newline separator when existing text is non-empty, and preserve existing user text exactly otherwise. Place the inline voice control below the `AnswerComposerView`, use the existing resolved speech dependencies, and call the helper when transcription completes. Keep the existing “提交回答” button as the only operation that creates an attempt and starts scoring.

- [ ] **Step 5: Run voice and editor tests**

Run both focused test suites again. Expected: successful transcription appends immediately, cancellation removes the local draft file, permission errors remain visible, and no recording action creates a persisted attempt before the user submits.

### Task 4: Add shared local search logic

**Files:**
- Modify: `InterviewFlashcard/Features/History/HistoryQuery.swift`.
- Create: `InterviewFlashcard/Features/Library/LibrarySearch.swift`.
- Test: `InterviewFlashcardTests/HistoryQueryTests.swift`.
- Test: `InterviewFlashcardTests/LibrarySearchTests.swift`.

**Interfaces:**
- Consumes: `AnswerAttemptRecord`, `QuestionCardRecord`, `TopicRecord`, and existing ordering rules.
- Produces: pure case-insensitive matching helpers with explicit active/trashed filtering and deterministic ordering.

- [ ] **Step 1: Write history search tests**

Cover these cases using the existing in-memory model container: a query matches `questionTextSnapshot`; a query matches `rawText`; a query matches the associated Topic name; matching is case-insensitive for Latin text; an empty query matches all visible attempts; and attempts for trashed questions are excluded regardless of the query.

- [ ] **Step 2: Write library search tests**

Cover question-text matches, Topic-name matches, case-insensitive matching, empty-query behavior, exclusion of trashed cards, and deterministic ordering by Topic library order followed by question creation date and UUID tie-breaker.

- [ ] **Step 3: Run the new tests to verify they fail**

Run:

```bash
xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'generic/platform=iOS Simulator' -only-testing:InterviewFlashcardTests/HistoryQueryTests -only-testing:InterviewFlashcardTests/LibrarySearchTests
```

Expected: the new helper symbols are not yet available or their expected behavior is not implemented.

- [ ] **Step 4: Implement the pure matching helpers**

Keep `HistoryQuery.global`’s newest-first behavior and add a predicate/helper that normalizes the query using localized case-insensitive/diacritic-insensitive matching over question snapshot, raw answer, and Topic name. Add `LibrarySearch` with a result type or static function that accepts active cards and returns matched cards in the documented deterministic order. Do not add network or database schema work.

- [ ] **Step 5: Run the helper tests to verify they pass**

Run the focused command again. Expected: all search helper tests pass and existing history query tests remain green.

### Task 5: Integrate history search and question-bank search

**Files:**
- Modify: `InterviewFlashcard/Features/History/HistoryView.swift`.
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift`.
- Modify: `InterviewFlashcard/Features/Library/QuestionDetailView.swift`.

**Interfaces:**
- Consumes: the search helpers from Task 4, existing `NavigationStack` destinations, and `AnswerEditorView(questionID:)`.
- Produces: searchable History and Library tabs plus a direct “开始回答” action from question details/search results.

- [ ] **Step 1: Add History search state and UI**

Add `.searchable(text:prompt:)` with a stable accessibility identifier. Apply the query to the existing visible attempts while preserving Topic Picker selection, result count, date ordering, score/status display, and detail navigation. Show an appropriate empty state for “no matching history” distinct from “no history yet”.

- [ ] **Step 2: Add Library search state and result presentation**

When the query is empty, preserve the existing Topic list and management actions. When non-empty, show a flat list of active question cards matched by question text or Topic name. Each result must open `QuestionDetailView`; include a clear direct-answer affordance where the row layout allows it without making the row’s detail navigation ambiguous.

- [ ] **Step 3: Add direct answer navigation to question details**

Add a prominent “开始回答” button or toolbar action in `QuestionDetailView` that navigates to `AnswerEditorView(questionID: question.id)`. The detail page must remain usable when opened from import results, Topic lists, or search results, and must continue to preserve trash/history actions.

- [ ] **Step 4: Build the feature targets and inspect accessibility identifiers**

Run:

```bash
xcodebuild build -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'generic/platform=iOS Simulator'
```

Expected: the app and core framework compile with the new navigation/search views. Confirm identifiers exist for History search, Library search, direct answer, and inline voice controls.

### Task 6: End-to-end regression verification

**Files:**
- Modify only the affected tests when a legitimate expectation changes: `InterviewFlashcardTests/AppShellTests.swift`, `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`, `InterviewFlashcardTests/HistoryQueryTests.swift`, `InterviewFlashcardTests/LibrarySearchTests.swift`, `InterviewFlashcardTests/AnswerEditorTests.swift`, and `InterviewFlashcardTests/PracticeCardLayoutTests.swift`.
- Review: `InterviewFlashcard/Features/Import/ImportView.swift`, `InterviewFlashcard/Features/Import/ImportCoordinator.swift`, and `InterviewFlashcard/Core/AI/StubAIClient.swift` to verify normal runtime boundaries.

**Interfaces:**
- Consumes: all production changes from Tasks 1–5.
- Produces: test evidence covering the requested feature set and a clean distinction between real runtime dependencies and explicit fixtures.

- [ ] **Step 1: Regenerate the Xcode project if new files are not visible**

Run `xcodegen generate` only if the checked-in project does not include newly created files from `project.yml`. Verify the generated project diff contains only the intended source/test references.

- [ ] **Step 2: Run the complete unit-test suite**

Run:

```bash
xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'generic/platform=iOS Simulator'
```

Expected: all existing import, persistence, AI validation, practice interaction, speech, history, and new search/editor tests pass. A test using Stub must select it explicitly; no test should rely on the new live default for deterministic assertions.

- [ ] **Step 3: Run a real-provider build path**

Build Debug with the project’s existing development configuration and verify the launch options resolve to DeepSeek when no Stub argument is supplied. Do not print or persist an API key. If a live network smoke test is available through the existing acceptance scripts, run it with the key supplied by the configured environment/keychain only.

- [ ] **Step 4: Verify the physical iPhone workflow**

Use the project’s `install-interviewflashcard-iphone` workflow to build, sign, install, launch, and inspect the physical iPhone. Verify the portrait practice card is larger and non-scrollable, the Library and History search fields filter real persisted data, the question detail opens Answer, and the inline voice control starts/stops local recording and appends a transcript when device permissions and on-device recognition are available. Save the required acceptance artifacts without selecting a simulator.

- [ ] **Step 5: Audit the final diff and worktree boundaries**

Run `git diff --check` and review only the files changed for this plan. Confirm unrelated pre-existing modifications remain untouched, no credentials appear in source/logs, and no normal UI path creates fixture/sample questions or silently falls back to Stub.

