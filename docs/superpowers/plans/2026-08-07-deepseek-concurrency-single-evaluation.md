# DeepSeek Concurrency and Single Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the per-answer polish request, add ASR-aware direct scoring, and run independent DeepSeek import/reclassification batches with bounded concurrency.

**Architecture:** Keep SwiftData mutations on `@MainActor`. Add a Sendable bounded task runner that executes only frozen request DTOs off the actor and returns indexed results; each service applies responses in deterministic ordinal order. Answer processing calls `evaluate` once with `polishedText == rawText` for compatibility and never creates a new polish record.

**Tech Stack:** Swift 6, Swift Concurrency (`TaskGroup`), SwiftData, XCTest, existing `AIClient`/`RetryingAIClient`, DeepSeek JSON API.

## Global Constraints

- The default AI request concurrency is exactly 3.
- Each refine/reclassification request contains at most 50 cards.
- AI task closures must not access `ModelContext` or SwiftData model objects.
- New answer processing must call `evaluate` exactly once and must not call `polish`.
- Existing polish records remain readable; new attempts may leave `EvaluationRecord.polishResultID` nil.
- Raw answer text remains the evidence source; the prompt must describe possible speech-to-text errors without allowing invented claims.
- A real DeepSeek run, not a stub run, is required for the final latency/result verification.

---

### Task 1: Add and test the bounded AI task runner

**Files:**
- Create: `InterviewFlashcard/Core/AI/BoundedAITaskRunner.swift`
- Create: `InterviewFlashcardTests/BoundedAITaskRunnerTests.swift`

**Interfaces:**
- Produces `BoundedAITaskRunner.run(inputs:limit:operation:) async -> [BoundedAITaskResult<Output>]`.
- `BoundedAITaskResult` contains the input index, an optional Sendable output, and a safe error description; results are returned in input order.

- [ ] **Step 1: Write the failing concurrency test**

Add an actor-backed counter to the test file. Run six async inputs with `limit: 3`, delay each operation briefly, and assert:

```swift
let results = await BoundedAITaskRunner.run(inputs: Array(0..<6), limit: 3) { value in
    await counter.started()
    try? await Task.sleep(nanoseconds: 20_000_000)
    await counter.finished()
    return value * 2
}
XCTAssertEqual(results.compactMap(\.value), [0, 2, 4, 6, 8, 10])
XCTAssertLessThanOrEqual(await counter.maximumActive(), 3)
```

Also add a test where one operation throws and assert the result preserves the other outputs and a non-empty error description for the failed index.

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
xcodebuild -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardTests/BoundedAITaskRunnerTests test
```

Expected: compile failure because `BoundedAITaskRunner` does not exist.

- [ ] **Step 3: Implement the runner**

Implement a nonisolated Sendable runner using `withTaskGroup`. Start at most `limit` tasks, add one replacement as each task completes, catch errors inside each task, and sort the indexed results before returning. Validate `limit > 0`; an empty input returns an empty result list. The operation closure receives only a Sendable input.

- [ ] **Step 4: Run the focused test to verify it passes**

Run the same `xcodebuild ... -only-testing:InterviewFlashcardTests/BoundedAITaskRunnerTests test` command. Expected: PASS, with maximum active work no greater than 3.

---

### Task 2: Convert answer processing to one direct evaluation request

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/AnswerProcessingService.swift`
- Modify: `InterviewFlashcard/Core/AI/PromptCatalog.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerComposerView.swift`
- Modify: `InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift`
- Modify: `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`
- Modify: `InterviewFlashcard/Features/History/HistoryQuery.swift`
- Modify: `InterviewFlashcard/Features/History/HistoryView.swift`
- Modify: `InterviewFlashcardTests/AnswerProcessingServiceTests.swift`
- Modify: `InterviewFlashcardTests/EndToEndWorkflowTests.swift`

**Interfaces:**
- `AnswerProcessingService.process` sets `.evaluating`, constructs `EvaluationRequest(polishedText: rawText, introducedClaims: [])`, calls `aiClient.evaluate` once, and creates `EvaluationRecord(polishResultID: nil)`.
- `PromptCatalog.evaluateVersion` becomes `evaluate-general-v2`; its prompt explains ASR uncertainty and requires evidence copied from `rawText`.

- [ ] **Step 1: Add a call-recording AI test double and update expectations**

In `AnswerProcessingServiceTests`, add an actor-backed `RecordingAIClient` whose `polish` increments a counter and whose `evaluate` records the request and returns the existing valid stub response. Change the success test to assert `polishCallCount == 0`, `evaluateCallCount == 1`, `request.rawText == request.polishedText`, `request.introducedClaims.isEmpty`, `attempt.polishResults.isEmpty`, and the same six scores/total. Update end-to-end and recovery assertions to expect no new polish record while retaining one evaluation.

- [ ] **Step 2: Run the focused tests to verify the old implementation fails**

Run:

```bash
xcodebuild -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardTests/AnswerProcessingServiceTests -only-testing:InterviewFlashcardTests/EndToEndWorkflowTests test
```

Expected: old tests fail because the current service calls `polish` and creates a polish record.

- [ ] **Step 3: Remove the polish call and update the evaluation prompt**

Change `AnswerProcessingService` to skip `.polishing`, `PolishRequest`, validation, and `PolishResultRecord`. Set `.evaluating`, save, call `evaluate` once with the raw answer in both text fields, and persist `polishResultID: nil`.

In `PromptCatalog`, add direct-evaluation rules: the answer may be an on-device ASR transcript; tolerate obvious homophones, missing punctuation, duplicated words, and dropped filler; infer only when the question/reference answer and remaining transcript support it; list uncertainty in `warnings`; never silently invent a technical claim. Remove the requirement that evaluation credit content present only in a polished answer.

Update visible copy from “AI 润色并评分” to “AI 评分中”, and replace the result/history “AI 润色后/润色版本” section with the submitted answer plus any existing legacy polish record only when one exists.

- [ ] **Step 4: Run the focused tests to verify the new behavior passes**

Run the same focused test command. Expected: PASS with one evaluation call and zero new polish records.

---

### Task 3: Parallelize Markdown decompose/refine while keeping persistence serial

**Files:**
- Modify: `InterviewFlashcard/Features/Import/ImportCoordinator.swift`
- Modify: `InterviewFlashcardTests/ImportCoordinatorTests.swift`

**Interfaces:**
- Add Sendable frozen work-item structs for decompose and refine requests.
- `decompose` and `refine` call `BoundedAITaskRunner.run(..., limit: 3)` and apply results on the main actor in ordinal order.

- [ ] **Step 1: Add import concurrency coverage**

Add an actor-backed AI client to `ImportCoordinatorTests` that records active calls, maximum concurrency, request IDs/chunk IDs, and returns valid responses from the existing stub implementation. Add a long Markdown test that creates at least six chunks and asserts the run is active, all cards are activated, and `maximumActive <= 3`. Add a refinement test with at least 151 candidates and assert exactly four 50/50/50/1 batches were sent and all results are staged in source order.

- [ ] **Step 2: Run the focused import tests to verify they fail**

Run:

```bash
xcodebuild -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardTests/ImportCoordinatorTests test
```

Expected: the new maximum-concurrency assertions fail because the existing loops await one request at a time.

- [ ] **Step 3: Freeze decompose inputs and run them in bounded batches**

Before launching tasks, mark all pending chunks as processing and save once. Build Sendable work items containing chunk ID/ordinal, source ID, owned Markdown, and decoded context envelope. Each task calls `aiClient.decompose`, validates anchors against its own frozen request, and returns the response or safe error text. On the main actor, sort results by ordinal, insert candidates for successful responses, mark successful chunks complete, mark failed chunks failed, save after the wave, and throw the first deterministic failure so the run remains recoverable.

- [ ] **Step 4: Freeze refine inputs and run 50-card batches concurrently**

Read topic names and decode all pending batch candidates before launching tasks. Each work item contains batch ID/ordinal, candidate IDs, and a Sendable `RefineRequest`. Tasks call `aiClient.refine` and validate response shape. Apply `stage` only on the main actor in ordinal order, update batch statuses, save once per result wave, and leave failed batches retryable without touching SwiftData from task closures.

- [ ] **Step 5: Run import tests to verify they pass**

Run the focused import test command again, then run the complete `ImportCoordinatorTests` suite. Expected: all tests pass, card order is deterministic, and concurrency never exceeds 3.

---

### Task 4: Parallelize Others reclassification batches

**Files:**
- Modify: `InterviewFlashcard/Features/Reclassification/ReclassificationService.swift`
- Modify: `InterviewFlashcardTests/ReclassificationServiceTests.swift`

**Interfaces:**
- `runAllOthers` freezes each 50-card `ReclassificationCard` request and executes batches through `BoundedAITaskRunner` with limit 3.
- Topic mutation, batch/run counters, progress callbacks, and saves stay on the main actor and are applied by batch ordinal.

- [ ] **Step 1: Add a max-concurrency assertion to the existing fixture**

Extend `ReclassificationAIStub` with active/max counters and a small async delay. Add a 151-card test and assert batch sizes `[50, 50, 50, 1]`, maximum active calls no greater than 3, and the final summary counts all successful cards.

- [ ] **Step 2: Implement frozen requests and ordered result application**

Mark all batch records processing in one save, create Sendable request snapshots, run them through the bounded runner, then validate assignments and mutate `QuestionCardRecord.topic` only while applying ordered results on the main actor. Failed responses mark only their batch failed and increment failed-card counts; final run status remains `completedWithFailures` when appropriate.

- [ ] **Step 3: Run reclassification tests**

Run the full `ReclassificationServiceTests` suite. Expected: existing failed-batch/unknown-topic behavior remains unchanged and new concurrency assertions pass.

---

### Task 5: Build, run regression tests, and perform a real DeepSeek latency check

**Files:**
- Modify: `docs/superpowers/specs/2026-08-06-deepseek-concurrency-single-evaluation-design.md` if implementation details materially change.
- Modify: `docs/acceptance/mvp-signoff.md` with the measured request count and latency.

- [ ] **Step 1: Run the complete test suite**

Run the project’s Debug test command against the pinned iPhone 17 Pro Max simulator. Expected: all unit and workflow tests pass; no Swift 6 concurrency warnings become errors.

- [ ] **Step 2: Build and launch the real DeepSeek configuration**

Run `source ~/.zshrc && scripts/dev/build-and-launch.sh --ai deepseek --speech unsupported --fixture real-question-demo --random-seed 20260805`, without printing the API key. Confirm the app launches with the renamed project environment variable and no stub provider.

- [ ] **Step 3: Submit one real answer and measure the request path**

Use the computer-use acceptance flow on iPhone 17 Pro Max, submit a real fixture answer, and poll until the result page appears. Verify diagnostics/SwiftData show `processingStatus=completed`, provider `deepseek-compatible`, one evaluation record, zero newly-created polish records, and a real six-dimension score. Compare elapsed time with the previous two-request run.

- [ ] **Step 4: Verify import/reclassification concurrency with a deterministic instrumented client**

Run the focused concurrency tests and retain their maximum-active-call assertions as the regression proof. Do not use a stub result as the real DeepSeek latency claim; report test concurrency separately from live API latency.

- [ ] **Step 5: Run `git diff --check` and report changed files and measurements**

Expected final report: single evaluation request per answer, bounded concurrency of 3 for independent batch operations, real DeepSeek result, and no exposed API key.
