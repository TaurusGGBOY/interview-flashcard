# Practice Card-First Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the “练习” and “随机” chrome from the populated practice home so the question card moves upward and becomes the page’s primary visual focus.

**Architecture:** Keep the current `PracticeView` → `PracticeFeedView` composition and all practice state unchanged. Make two presentation-only removals: the root navigation title in `PracticeView` and the header row in `PracticeFeedView`; the existing flexible card geometry will consume the released vertical space without adding a replacement component.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Xcode 27 beta, iOS 27 Simulator.

## Global Constraints

- Implement the approved design in `docs/superpowers/specs/2026-08-09-practice-card-first-home-design.md`.
- Preserve all swipe, skip, answer, undo, empty-state, topic-filtering, and navigation behavior.
- Preserve the existing horizontal safe-area padding and button hit areas.
- Do not add a replacement title, toolbar item, decoration, dependency, or persistence state.
- Preserve unrelated and pre-existing worktree changes. Because both production files already contain overlapping user changes, do not commit implementation files unless their full staged diff is explicitly reviewed and authorized.
- Build, install, launch, and visually verify only on iOS Simulator `779ACF98-BD23-4880-9F03-8DB9B9E43768`; never install this change on a physical device.

---

### Task 1: Make the populated practice feed card-first

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift:60-93`
- Modify: `InterviewFlashcard/Features/Practice/PracticeFeedView.swift:26-88`
- Verify: `InterviewFlashcardTests/AppShellTests.swift`
- Verify: `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift`

**Interfaces:**
- Consumes: the existing `PracticeFeedView` initializer, `PracticeSwipeActionLayer`, `QuestionCardView`, and `PracticeAccessibilityID` values without signature changes.
- Produces: the same practice feed and navigation behavior with no root title row above the card.

- [ ] **Step 1: Record the current failing visual contract**

Launch the current simulator build with an existing populated practice fixture. Capture accessibility text and a screenshot showing the unwanted `练习` heading and `随机` label above the question card. Treat their presence and the card’s lower top edge as the pre-change failure evidence.

- [ ] **Step 2: Remove the root practice navigation title**

In `PracticeView.body`, remove only the `练习` navigation-title modifier. Keep the navigation destination and all lifecycle/change handlers in their existing order and behavior. Do not hide the navigation bar globally because the pushed answer editor must retain its normal navigation affordance.

- [ ] **Step 3: Remove the populated-feed header row**

In `PracticeFeedView.cardFeed`, remove the complete header row that renders the `随机` label and its icon. Keep the existing `VStack` spacing, flexible `GeometryReader`, card minimum height, swipe layer, hint, buttons, undo control, safe-area padding, and accessibility identifiers unchanged so the card naturally consumes the released height.

- [ ] **Step 4: Verify the removed chrome is absent from source**

Run:

```bash
rg -n 'navigationTitle\("练习"\)|Label\("随机"' InterviewFlashcard/Features/Practice/PracticeView.swift InterviewFlashcard/Features/Practice/PracticeFeedView.swift
```

Expected: no matches. Inspect the focused diff to confirm no state, action, empty-state, or navigation code changed.

- [ ] **Step 5: Run focused regression tests**

Run:

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -derivedDataPath build/PracticeCardFirstDerivedData \
  -only-testing:InterviewFlashcardTests/AppShellTests \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests
```

Expected: both suites pass with zero failures, proving the tab shell, global-empty routing, answer routing, swipe threshold, skip/answer action mapping, and undo behavior remain intact.

### Task 2: Prove the final layout and repository state

**Files:**
- Verify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Verify: `InterviewFlashcard/Features/Practice/PracticeFeedView.swift`
- Create: `diagnostics/acceptance/practice-card-first-home/01-card-first-home.jpeg`
- Verify: `build/PracticeCardFirstDerivedData/Logs/Test/*.xcresult`

**Interfaces:**
- Consumes: the simulator app built by Task 1 and the existing populated simulator data.
- Produces: test results and visual evidence for every acceptance criterion in the design.

- [ ] **Step 1: Run the full test suite**

Run the complete `InterviewFlashcard` scheme test action with the same Xcode, exact simulator UDID, and derived-data path used in Task 1, but without `-only-testing` filters.

Expected: all discovered tests pass with zero failures. Use `xcresulttool get test-results summary` on the generated result bundle to record the authoritative count.

- [ ] **Step 2: Build the simulator application**

Run `xcodebuild build` for the `InterviewFlashcard` scheme with destination `platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768` and derived data `build/PracticeCardFirstDerivedData`.

Expected: `BUILD SUCCEEDED` and the product exists at `build/PracticeCardFirstDerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app`.

- [ ] **Step 3: Install and launch on the exact simulator only**

Use `simctl bootstatus`, `simctl install`, and `simctl launch` with UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`. Launch with the stub AI provider and diagnostics enabled. Do not use `booted`, a generic iOS destination, `iphoneos`, or any physical-device command.

Expected: `simctl list devices` identifies the exact target as `iPhone 17 Pro Max` and `Booted`, and the app launches with bundle identifier `com.gaoguobin.InterviewFlashcard`.

- [ ] **Step 4: Perform Computer Use visual acceptance**

Inspect the Device Hub simulator window through Computer Use. On a populated practice feed, verify the accessibility tree does not contain a practice-page `练习` heading or `随机` label; verify the question card starts near the top safe area and is visibly taller; verify the card, swipe hint, `跳过`, and `开始回答` controls all remain visible without overlap.

Capture the final screenshot as `diagnostics/acceptance/practice-card-first-home/01-card-first-home.jpeg`. Distinguish the app UI from Device Hub’s own toolbar controls when evaluating accessibility text.

- [ ] **Step 5: Audit unchanged behavior and the focused diff**

Verify a skip or answer action still responds, then return to the populated feed without deleting user data. Run `git diff --check` and inspect only the two production files plus this plan. Confirm the implementation changed presentation chrome only, preserved the dirty worktree, and created no physical-device artifact or installation.
