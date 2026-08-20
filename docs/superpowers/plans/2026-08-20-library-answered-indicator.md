# Library Answered Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a small, accessible answered-state checkmark on previously answered questions in both library list variants.

**Architecture:** Derive answered state from the existing `QuestionCardRecord.attempts` relationship through a non-persisted model property, so no schema migration or duplicate state is introduced. `LibraryView` consumes that property through one reusable indicator and one reusable accessibility-label helper, keeping Topic-expanded rows and search-result rows consistent.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, XCTest, SF Symbols, iOS 26.0, XcodeGen

## Global Constraints

- A question is answered when it has at least one persisted `AnswerAttemptRecord`.
- A saved attempt remains answered even when its later AI scoring status is `.failed`.
- Do not add a persistent field, cache, hash, schema migration, dependency, answer count, score, or timestamp.
- Show `checkmark.circle.fill` in system green only during normal browsing.
- Show the same state in Topic-expanded question rows and search-result rows.
- Hide the answered indicator during batch-selection mode.
- VoiceOver must announce “已回答” for answered rows and must not announce it for unanswered rows.
- Do not alter question ordering, tapping, long-press selection, navigation, answer submission, scoring, or history behavior.

---

## File Structure

- Modify `InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift`: expose the derived, non-persisted answered-state property beside the existing model state helpers.
- Create `InterviewFlashcardTests/QuestionAnsweredStateTests.swift`: verify unanswered, answered, and failed-processing-attempt semantics using the in-memory SwiftData test container.
- Modify `InterviewFlashcard/Features/Library/LibraryView.swift`: render and announce the answered state consistently in both question-row variants.

### Task 1: Derived Answered State

**Files:**
- Modify: `InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift:20-24`
- Create: `InterviewFlashcardTests/QuestionAnsweredStateTests.swift`

**Interfaces:**
- Consumes: `QuestionCardRecord.attempts: [AnswerAttemptRecord]`
- Produces: `QuestionCardRecord.hasBeenAnswered: Bool`, returning whether `attempts` is non-empty without inspecting processing or evaluation status

- [ ] **Step 1: Write the failing model tests**

Create three `@MainActor` XCTest cases backed by `TestModelContainer.make()`. Use `Fixtures.makeCard` for the question. Verify that a new question reports false, a question with a persisted `.saved` attempt reports true, and a question with a persisted `.failed` attempt reports true. The failed case must set only attempt processing state to failed; it must not create an evaluation, proving that score success is irrelevant.

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer scripts/dev/test.sh -only-testing:InterviewFlashcardTests/QuestionAnsweredStateTests
```

Expected: build or test failure because `QuestionCardRecord.hasBeenAnswered` does not exist.

- [ ] **Step 3: Implement the derived property**

Add a read-only, non-persisted `Bool` property to `QuestionCardRecord` next to `isTrashed`. It must return true exactly when the existing `attempts` relationship is non-empty. It must not branch on `processingStatus`, `evaluations`, or any AI result.

- [ ] **Step 4: Run the focused tests to verify they pass**

Run the command from Step 2 again.

Expected: all three `QuestionAnsweredStateTests` pass.

- [ ] **Step 5: Commit the domain behavior**

```bash
git add InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift InterviewFlashcardTests/QuestionAnsweredStateTests.swift
git commit -m "feat: derive answered state for questions"
```

### Task 2: Library Row Indicator and Accessibility

**Files:**
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift:340-448`

**Interfaces:**
- Consumes: `QuestionCardRecord.hasBeenAnswered: Bool` from Task 1 and `LibraryView.isSelectingQuestions: Bool`
- Produces: one private answered-indicator view helper and one private normal-browsing accessibility-label helper shared by both question-row variants

- [ ] **Step 1: Add the reusable presentation helpers**

Add a private `@ViewBuilder` helper that emits `Image(systemName: "checkmark.circle.fill")` only when the question has been answered and batch selection is inactive. Style it with semantic system green, keep it non-interactive, hide the icon itself from VoiceOver, and prevent it from shrinking ahead of the question text.

Add a private string helper for normal-browsing row labels. It must return the original question text for unanswered questions and the question text followed by the state “已回答” for answered questions. Selection-mode labels must continue using the existing selection-specific wording without the answered suffix.

- [ ] **Step 2: Integrate the helpers into search-result rows**

Place the indicator at the trailing edge of `searchableQuestionRow`, after its title/topic content. Preserve the current leading selection circle, topic caption, full-width alignment, one-line truncation, padding, border, gestures, identifiers, and button behavior. Switch the normal-browsing accessibility label from raw question text to the shared label helper.

- [ ] **Step 3: Integrate the helpers into Topic-expanded rows**

Place the same trailing indicator after the numbered question content in `topicQuestions`. Preserve the current leading selection circle, number, one-line truncation, padding, border, gestures, identifiers, ordering, and button behavior. Switch the normal-browsing accessibility label to the same shared label helper.

- [ ] **Step 4: Run focused and adjacent library tests**

Run:

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer scripts/dev/test.sh \
  -only-testing:InterviewFlashcardTests/QuestionAnsweredStateTests \
  -only-testing:InterviewFlashcardTests/LibraryQuestionOrderingTests \
  -only-testing:InterviewFlashcardTests/LibrarySearchTests
```

Expected: all selected tests pass and `LibraryView` compiles under Swift 6 strict concurrency.

- [ ] **Step 5: Commit the library presentation**

```bash
git add InterviewFlashcard/Features/Library/LibraryView.swift
git commit -m "feat: mark answered questions in library"
```

### Task 3: Regression and Interface Verification

**Files:**
- Verify only; no planned source changes

**Interfaces:**
- Consumes: completed model and library presentation from Tasks 1–2
- Produces: evidence that the feature does not regress the project and matches the approved visual/accessibility behavior

- [ ] **Step 1: Run the complete unit-test target**

Run:

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer scripts/dev/test.sh -only-testing:InterviewFlashcardTests
```

Expected: the complete `InterviewFlashcardTests` target passes. If unrelated pre-existing worktree changes cause a failure, record the exact failing suite and verify that the focused suites from Task 2 still pass; do not modify or discard the user's unrelated changes.

- [ ] **Step 2: Launch and inspect the library UI**

Use the project development launcher with the configured iOS simulator, then verify: an answered Topic-expanded row has a green trailing checkmark; an unanswered row has no marker; search results match; entering batch selection hides the answered marker; exiting restores it; light and dark appearances remain legible.

- [ ] **Step 3: Verify accessibility semantics**

Inspect the accessibility representation of both row variants. Confirm an answered row announces its question plus “已回答”, an unanswered row omits the status, the decorative icon is not announced separately, and selection mode retains the existing “选择题目/取消选择题目” semantics.

- [ ] **Step 4: Review the final diff and repository state**

Run:

```bash
git diff --check
git status --short
git log -3 --oneline
```

Expected: no whitespace errors; feature files are committed; pre-existing AI-related user modifications remain present and untouched.
