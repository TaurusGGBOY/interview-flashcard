# Background Import Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Markdown 导入改成“后台分析整理 → 用户一次确认 → 全量写入题库”的两阶段流程，用户不再因为 LLM 导入耗时而停留在导入页。

**Architecture:** 导入文件后先持久化 `ImportRunRecord`、分片和候选题，立即把控制权还给界面；后台沿用现有通用 LLM 分析、答案整理、Topic 归类和持久化恢复链路，完成后将 run 标记为 `ready`，但不创建 `QuestionCardRecord`。新增显式确认操作只调用本地激活事务，一次性把该 run 的全部已验证候选题写入已有 Topic；确认前题库中不可见，确认后沿用现有题目详情/Topic 编辑入口。

**Tech Stack:** SwiftUI, SwiftData, Swift Concurrency, XCTest, iOS Simulator.

## Global Constraints

- 只保留通用 LLM 导入链路；不得按标题编号、Markdown 形状或固定格式写确定性题目提取器。
- 用户不能逐题勾选、删选或决定是否导入；`ready` run 只能执行一次“全部导入”。
- 后台分析完成前不创建题库卡片；后台分析完成后也不自动创建卡片。
- App 退出或重启时，`queued`/分析中/整理中的 run 必须可恢复；`ready` run 必须保持待确认，不能被启动恢复自动导入。
- 未知或不存在的 Topic 继续回退到系统 `Others`，不得因为单个 Topic 名称异常而丢弃整批题目。
- 确认导入必须是幂等的；重复点击或重复恢复不能创建重复卡片。
- 移除本轮真实验收使用的 DEBUG 自动导入启动参数，正式 App 不暴露测试入口。

---

### Task 1: 建立“待确认”持久化状态

**Files:**
- Modify: `InterviewFlashcard/Core/Domain/DomainEnums.swift`
- Modify: `InterviewFlashcard/Core/Persistence/Models/ImportRecord.swift` only if model-facing helpers need status naming
- Modify: `InterviewFlashcard/Core/Recovery/LaunchRecoveryCoordinator.swift`
- Modify: `InterviewFlashcard/Core/Persistence/DiagnosticStateExporter.swift` if its status projection needs explicit ready-state coverage
- Test: `InterviewFlashcardTests/LaunchRecoveryCoordinatorTests.swift` or the existing recovery test file
- Test: `InterviewFlashcardTests/ImportCoordinatorTests.swift`

**Interfaces:**
- Produces a new persisted `ImportRunStatus` value named `ready` (or an equally explicit ready-for-confirmation name), used by coordinator and UI.
- Recovery treats `ready` as terminal-but-unactivated: it does not call `continueRun` for this state.
- Existing `active` and `failed` semantics remain unchanged.

- [ ] **Step 1: Write the failing tests**

Add tests that decode/compare the new status, verify a ready run is not considered resumable, and verify diagnostic state can report a ready run without cards. Keep a separate assertion that queued/decomposing/refining runs remain resumable.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer xcodebuild -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' test -only-testing:InterviewFlashcardTests/ImportCoordinatorTests -only-testing:InterviewFlashcardTests/LaunchRecoveryCoordinatorTests
```

Expected: the new ready-state assertions fail because no ready status or recovery branch exists yet.

- [ ] **Step 3: Add the status and recovery behavior**

Add the new status to the persisted enum and make recovery stop its import loop for ready runs while retaining retry behavior for all in-progress states. Keep diagnostic serialization descriptive enough for the UI/evidence to distinguish “后台处理中” from “等待一键导入”.

- [ ] **Step 4: Run the focused tests and verify pass**

Run the same focused command. Expected: all status/recovery tests pass.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Core/Domain/DomainEnums.swift InterviewFlashcard/Core/Recovery/LaunchRecoveryCoordinator.swift InterviewFlashcard/Core/Persistence/DiagnosticStateExporter.swift InterviewFlashcardTests/ImportCoordinatorTests.swift InterviewFlashcardTests/LaunchRecoveryCoordinatorTests.swift
git commit -m "feat: persist background import ready state"
```

### Task 2: 把导入协调器拆成“排队、后台分析、确认激活”

**Files:**
- Modify: `InterviewFlashcard/Features/Import/ImportCoordinator.swift`
- Modify: `InterviewFlashcard/App/AppRuntime.swift` to keep startup recovery background-only and remove the temporary DEBUG import hook
- Modify: `InterviewFlashcard/Features/Import/ImportView.swift` call sites after the coordinator API changes
- Test: `InterviewFlashcardTests/ImportCoordinatorTests.swift`

**Interfaces:**
- `start(urls:)` persists all selected files and returns their run IDs after enqueueing background processing; it must not await LLM completion.
- Existing direct Markdown test helper may remain synchronous if needed for deterministic unit tests, but production file selection must use the non-blocking enqueue path.
- `continueRun(id:)` remains available for recovery/retry and completes the analysis phase only.
- Add `confirmImport(id:) async throws` or an equivalent public coordinator method. It validates that the run is ready, performs the existing activation transaction for every refined candidate, saves once, and is idempotent for active runs.
- Background completion changes the run to `ready`; it never calls activation automatically.

- [ ] **Step 1: Write the failing coordinator tests**

Cover these concrete cases:

1. A delayed fake LLM plus `start(urls:)` returns promptly while the run is queued/decomposing/refining, with zero question cards; after the background task finishes the run is ready and candidates exist.
2. Calling `confirmImport(id:)` on that ready run creates every candidate card, preserves candidate order, assigns the proposed/known Topic or `Others`, and changes the run to active.
3. Calling `confirmImport(id:)` twice leaves the same card count and does not duplicate reference answers.
4. A failed background run has zero cards; retrying analysis produces ready, and only a later confirmation creates cards.
5. A ready run is not auto-activated by `LaunchRecoveryCoordinator`.

Update existing import tests that currently expect `start` to end in active: they must assert ready/no cards first, then explicitly confirm and assert active/cards. Preserve the generic-AI-path assertions and bounded concurrency assertions.

- [ ] **Step 2: Run the focused coordinator tests and verify failure**

Run the ImportCoordinator and recovery test targets. Expected: current implementation either blocks until LLM work finishes or activates immediately, so the new asynchronous/ready assertions fail.

- [ ] **Step 3: Split persistence from processing**

Extract the current source/run/chunk creation work into a persistence-only phase. For each selected URL, read/decode/copy the source, insert the run and all chunks, save, then create one background MainActor task that processes the persisted runs. Return IDs immediately after this phase. Use the existing process/decompose/refine logic unchanged for candidate generation and validation, retaining the single-pass production LLM path and its full-score validation.

- [ ] **Step 4: Stop automatic activation and add explicit confirmation**

Change process completion to set ready and persist. Make activation callable only through the new confirmation method, retain all existing anchor/topic/answer validation, and keep the existing “already active” early return so duplicate confirmations are harmless. Do not expose candidate-selection parameters.

- [ ] **Step 5: Remove the temporary DEBUG import hook**

Delete the temporary `-IFImportFile` launch-argument code added to `AppRuntime.swift` for the interrupted real-App timing test. Normal launch must only run persisted recovery, never start an import from an argument.

- [ ] **Step 6: Run the focused tests and verify pass**

Run the updated ImportCoordinator, recovery, persistence, and end-to-end local workflow tests. Expected: enqueue is non-blocking, ready has no cards, confirmation creates all cards, and existing answer/topic behavior remains valid.

- [ ] **Step 7: Commit**

```bash
git add InterviewFlashcard/Features/Import/ImportCoordinator.swift InterviewFlashcard/App/AppRuntime.swift InterviewFlashcardTests/ImportCoordinatorTests.swift InterviewFlashcardTests/LaunchRecoveryCoordinatorTests.swift
git commit -m "feat: separate background import analysis from activation"
```

### Task 3: Add the read-only review and one-click import UI

**Files:**
- Modify: `InterviewFlashcard/Features/Import/ImportView.swift`
- Create: `InterviewFlashcard/Features/Import/ImportReviewView.swift` if the review screen does not fit the current file cleanly
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift` or the import-local accessibility ID definition
- Test: `InterviewFlashcardTests/AppShellTests.swift` and any existing import UI/accessibility tests

**Interfaces:**
- Ready rows navigate to a read-only review screen for the run, not directly to activated cards.
- Review screen consumes an `ImportRunRecord` and the environment’s `ImportCoordinator` dependencies.
- Review screen exposes exactly one import action for the whole run, with a stable accessibility identifier; it has no checkbox, per-question toggle, delete, skip, or partial-import control.

- [ ] **Step 1: Write the failing UI behavior tests**

Assert the status copy and accessibility contract: processing rows say the work is happening in the background, ready rows expose a review/confirmation destination, the review screen exposes “一键导入全部题目”, and no per-candidate selection control exists. Assert the active row continues to expose the existing generated-card path.

- [ ] **Step 2: Run the focused UI/app-shell tests and verify failure**

Run the relevant AppShell/import UI tests. Expected: the current view has only an automatic active link and no ready review or confirmation action.

- [ ] **Step 3: Implement the non-blocking import list**

Remove the long-lived spinner behavior from the file-selection task: it may indicate only the short enqueue operation. Render run status/counts from SwiftData so leaving and returning to the tab shows live progress. For ready runs, show the analyzed question count and a navigation affordance to review.

- [ ] **Step 4: Implement the read-only review screen**

Display all analyzed candidates in source order, including question text and the proposed Topic/`Others`, as read-only information. Put one prominent confirmation button at the bottom/top. On tap, invoke `confirmImport`, show a short local progress state only for activation, then return to the active result or the existing generated-card list. Surface failures without losing the ready candidates.

- [ ] **Step 5: Connect editing to the existing Topic/card paths**

After activation, retain the existing cards-to-`QuestionDetailView` path and the Library Topic question list/editor path. Do not add editing controls to the import review screen; imported question/answer modifications happen in their Topic/card destination.

- [ ] **Step 6: Run focused tests and verify pass**

Run the UI/app-shell tests and the coordinator tests together. Expected: users can leave the import tab during analysis, ready runs require exactly one all-in confirmation, and active cards remain editable through existing Topic/card screens.

- [ ] **Step 7: Commit**

```bash
git add InterviewFlashcard/Features/Import/ImportView.swift InterviewFlashcard/Features/Import/ImportReviewView.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/AppShellTests.swift
git commit -m "feat: add one-click background import confirmation"
```

### Task 4: Verify persistence, recovery, and production build

**Files:**
- Modify only the tests/docs needed by the verification findings.
- Verify: `InterviewFlashcard/Features/Import/ImportCoordinator.swift`, `InterviewFlashcard/Core/Recovery/LaunchRecoveryCoordinator.swift`, `InterviewFlashcard/Features/Import/ImportView.swift`, and the model/status files.

**Interfaces:**
- The final workflow has three observable states: processing, ready for confirmation, active.
- Cards are absent in processing/ready and present only after confirmation.

- [ ] **Step 1: Run all relevant local tests**

Run the complete test target or the project’s supported test script with the iOS Simulator destination. Include import, recovery, persistence, topic, library, and end-to-end workflow tests.

- [ ] **Step 2: Perform a real App smoke test**

Build/install the current App with the existing development launcher and real configured provider. Import the requested Markdown through the App’s import flow or its controlled acceptance path. Record that the UI returns immediately, background status progresses, ready appears with all analyzed questions, no cards exist before confirmation, and one confirmation creates all cards.

- [ ] **Step 3: Verify relaunch behavior**

Terminate/relaunch during analysis and confirm the run resumes; terminate/relaunch while ready and confirm it remains ready with no cards; confirm once and verify cards appear under their Topics.

- [ ] **Step 4: Verify source and answer integrity**

Confirm all cards retain source anchors, validated reference answers, topic fallback behavior, and no deterministic heading-based extraction code or fake/stub production path was introduced.

- [ ] **Step 5: Remove temporary artifacts and report evidence**

Remove any temporary live tests, debug launch hooks, screenshots, or diagnostic files created solely for the interrupted timing experiment. Report build/test commands and the observed state transitions.

- [ ] **Step 6: Commit**

```bash
git add InterviewFlashcard docs/superpowers/plans/2026-08-11-background-import-confirmation.md
git commit -m "test: verify background import confirmation workflow"
```
