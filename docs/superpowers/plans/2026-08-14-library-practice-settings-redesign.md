# 题库、练习与设置页重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为题库、练习和设置页实现已批准的交互重做，并为所有题目建立导入时确定的全库递增编号。

**Architecture:** 保留现有 SwiftUI + SwiftData 架构。新增一个主线程上的题目编号服务负责分配和回填编号；TopicService 增加不可撤销的 Topic 级联删除能力；现有导入、评分、历史和回收站链路只在必要位置接入新行为。题库继续由 `LibraryView` 管理页面状态，设置页改为根列表导航到两个独立的分组表单。

**Tech Stack:** Swift 6.0, SwiftUI, SwiftData, XCTest, XcodeGen, iOS 26.0 deployment target.

## Global Constraints

- 题目编号是全库递增的永久唯一整数，不显示 `#`。
- 编号在题目导入最终激活时确定；手动新增题目继续使用下一个编号。
- 题目编号不会因为移动 Topic、删除题目或重新导入而复用。
- Topic 内的题目按编号从大到小显示。
- 题目长按进入多选；多选状态下点击任何非题目区域立即退出多选。
- Topic 不进入多选状态，也不提供 Topic 批量删除。
- Topic 只能通过左滑删除；确认后删除 Topic 及其全部题目，且不可撤销。
- 语音回答整块从回答页移除，不再提供新的录音或本地语音转写功能；旧语音记录保持可读和可清理。
- 保持现有导入、AI 分类、评分、历史评分展示、回收站和 AI provider 语义不变。
- 不增加 Swift Package 依赖；保留当前 iOS 26.0 deployment target 和 Swift 6.0 strict concurrency 设置。
- 工作树中已有改动属于用户，只修改本计划列出的文件，不执行 reset、checkout 或大范围格式化。

## File Map

- Create: `InterviewFlashcard/Core/Persistence/QuestionNumberingService.swift` — 分配新编号、稳定回填旧题。
- Modify: `InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift` — 增加兼容迁移用的可选题目编号。
- Modify: `InterviewFlashcard/Core/Persistence/AppRuntime.swift` — 启动 bootstrap 时回填编号。
- Modify: `InterviewFlashcard/Features/Import/ImportCoordinator.swift` — 激活导入题目时分配编号。
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift` — 题库布局、题目编号、多选退出、Topic 左滑删除和加号位置。
- Modify: `InterviewFlashcard/Features/Library/TopicService.swift` — Topic 级联删除及音频文件清理依赖。
- Modify: `InterviewFlashcard/Features/Trash/TrashService.swift` — 复用本地音频文件清理实现。
- Modify: `InterviewFlashcard/Features/Settings/SettingsView.swift` — 根设置页改为分组导航列表。
- Modify: `InterviewFlashcard/Features/Settings/AIServiceSettingsView.swift` — AI 设置页分组排版。
- Modify: `InterviewFlashcard/Features/Settings/PracticeSettingsView.swift` — 练习设置页分组排版。
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift` — 增加设置根页导航行 identifier。
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift` — 删除练习标题和语音回答区域，只保留文字提交。
- Modify: `InterviewFlashcard/Features/Practice/AnswerSubmissionService.swift` — 保留文字提交，移除生产语音提交接口。
- Modify: `InterviewFlashcard/App/AppEnvironment.swift` — 移除语音能力注入和运行时开关。
- Modify: `InterviewFlashcard/App/InterviewFlashcard-Info.plist` — 删除麦克风和语音识别权限说明。
- Modify: `InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift` — 为验收夹具提供稳定编号或触发编号回填。
- Modify: `InterviewFlashcardTests/Support/TestModelContainer.swift` — 保持测试 schema 包含新字段。
- Modify: `InterviewFlashcardTests/ImportCoordinatorTests.swift`, `InterviewFlashcardTests/PersistenceTests.swift`, `InterviewFlashcardTests/TopicServiceTests.swift` — 覆盖编号、导入和级联删除。
- Create: `InterviewFlashcardTests/QuestionNumberingServiceTests.swift` — 编号服务的单元测试。
- Create: `InterviewFlashcardTests/LibraryQuestionOrderingTests.swift` — Topic 内题目降序规则测试。
- Modify: `InterviewFlashcardTests/AnswerSubmissionServiceTests.swift`, `InterviewFlashcardTests/AnswerEditorTests.swift`, `InterviewFlashcardTests/AppShellTests.swift` — 验证文字回答路径和语音开关移除后的行为。
- Modify: `InterviewFlashcardTests/AppShellTests.swift` — 验证设置导航 identifier 契约。
- Delete: `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`, `InterviewFlashcard/Core/Speech/SpeechTranscribing.swift`, `InterviewFlashcard/Core/Speech/AppleSpeechTranscriber.swift`, `InterviewFlashcard/Core/Speech/AudioRecording.swift` — 删除不再使用的录音/转写运行时代码。
- Delete: `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`, `InterviewFlashcardTests/SpeechCapabilityTests.swift` — 删除已取消功能的测试，保留旧语音持久化/历史清理测试在现有数据模型测试中。

---

### Task 1: 建立全库题目编号服务

**Files:**
- Create: `InterviewFlashcard/Core/Persistence/QuestionNumberingService.swift`
- Modify: `InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift`
- Test: `InterviewFlashcardTests/QuestionNumberingServiceTests.swift`
- Test: `InterviewFlashcardTests/Support/TestModelContainer.swift`

**Interfaces:**
- Produces `@MainActor struct QuestionNumberingService`。
- Produces `nextNumber(context: ModelContext) throws -> Int`，返回当前最大正编号加一；没有编号时返回 1。
- Produces `backfillIfNeeded(context: ModelContext) throws`，只为 `questionNumber == nil` 的题目赋值，按 `createdAt` 升序、UUID 字符串升序处理。
- `QuestionCardRecord.questionNumber` 类型为 `Int?`，仅在旧 store 迁移窗口内允许为 nil。

- [ ] **Step 1: 写失败测试**

在 `QuestionNumberingServiceTests.swift` 中覆盖：空题库首次分配为 1；已有编号 1、2 时下一题为 3；删除编号 2 后下一题仍为 4；旧题按创建时间和 UUID 稳定回填；重复执行回填不会改动已有编号。

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodegen generate && DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/QuestionNumberingServiceTests`

Expected: FAIL because `questionNumber` and `QuestionNumberingService` are not implemented.

- [ ] **Step 3: 实现最小编号服务**

给题目模型加入可选编号；服务查询当前题目集合的最大正编号，分配下一个未使用的整数，并在回填时只处理 nil 记录。回填和分配都必须在传入的主 ModelContext 上执行，不依赖时间戳作为新编号，不复用删除过的编号。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/QuestionNumberingServiceTests`

Expected: PASS with all numbering allocation and stable backfill cases passing.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Core/Persistence/QuestionNumberingService.swift InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift InterviewFlashcardTests/QuestionNumberingServiceTests.swift InterviewFlashcardTests/Support/TestModelContainer.swift
git commit -m "feat: add persistent question numbering"
```

### Task 2: 将编号接入启动、导入、手动新增和验收夹具

**Files:**
- Modify: `InterviewFlashcard/App/AppRuntime.swift`
- Modify: `InterviewFlashcard/Features/Import/ImportCoordinator.swift`
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift` (manual question creation only)
- Modify: `InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift`
- Modify: `InterviewFlashcardTests/ImportCoordinatorTests.swift`
- Modify: `InterviewFlashcardTests/PersistenceTests.swift`

**Interfaces:**
- Consumes `QuestionNumberingService.nextNumber(context:)` and `backfillIfNeeded(context:)` from Task 1.
- Produces an invariant that every active card has a non-nil number after `AppRuntime.prepareServices()` and before the first visible library render.

- [ ] **Step 1: 写失败测试**

在导入测试中构造按 `sourceOrder` 排序的多个候选题，激活后断言题目编号连续且顺序与 `sourceOrder` 一致；在持久化测试中构造 nil 编号旧题并运行 bootstrap 需要调用的回填路径；在手动题目测试路径中断言新题编号大于现有最大编号。

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/ImportCoordinatorTests -only-testing:InterviewFlashcardTests/PersistenceTests`

Expected: FAIL because activation, bootstrap and manual creation do not assign numbers.

- [ ] **Step 3: 接入生命周期**

在 `AppRuntime` 完成 Others bootstrap 后调用回填并保存；在 `ImportCoordinator.activate` 的 `sourceOrder` 排序计划中为每个新卡分配编号并与卡片插入同一保存周期；在 `ManualQuestionEditorView.save` 中为新卡分配编号；验收夹具使用显式稳定编号或同一编号服务，避免 UI 验收顺序漂移。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/ImportCoordinatorTests -only-testing:InterviewFlashcardTests/PersistenceTests`

Expected: PASS; existing import status, source order and persistence assertions remain valid, with new numbering assertions passing.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/App/AppRuntime.swift InterviewFlashcard/Features/Import/ImportCoordinator.swift InterviewFlashcard/Features/Library/LibraryView.swift InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift InterviewFlashcardTests/ImportCoordinatorTests.swift InterviewFlashcardTests/PersistenceTests.swift
git commit -m "feat: assign question numbers during activation"
```

### Task 3: 增加 Topic 级联删除服务

**Files:**
- Modify: `InterviewFlashcard/Features/Library/TopicService.swift`
- Modify: `InterviewFlashcard/Features/Trash/TrashService.swift` — 将现有本地音频移除 helper 暴露给同模块的 TopicService 注入点。
- Modify: `InterviewFlashcardTests/TopicServiceTests.swift`
- Modify: `InterviewFlashcardTests/TrashServiceTests.swift`

**Interfaces:**
- Produces `TopicService.TopicDeletionImpact` containing topic ID, question count, answer count, evaluation count and audio count for confirmation copy.
- Produces `deletionImpact(for:context:) throws -> TopicDeletionImpact`.
- Produces `permanentlyDelete(topic:context:) throws` that rejects system Topics, captures all legacy audio paths, deletes the Topic graph in SwiftData, saves successfully, then removes captured audio files through the injected `TrashService.removeAudioFile` function.
- Existing `delete(_:moveCardsTo:context:)` remains available for compatibility with prior service tests and is not used by the new swipe action.

- [ ] **Step 1: 写失败测试**

在 `TopicServiceTests` 中构造一个普通 Topic、两道题、回答、评分和一个 AudioAssetRecord；断言 deletion impact 统计准确，确认删除后 Topic、题目、回答、评分和音频记录都不存在，注入的音频移除闭包收到正确路径；另测 Others 删除抛出 `.systemTopicIsImmutable`。验证题目编号在删除其他 Topic 后仍不被服务复用由编号服务测试覆盖。

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/TopicServiceTests`

Expected: FAIL because the impact and permanent Topic deletion interfaces do not exist.

- [ ] **Step 3: 实现级联删除**

添加独立于旧“迁移题目到目标 Topic”逻辑的永久删除入口。删除前读取影响统计和所有音频相对路径；只在 SwiftData 保存成功后调用文件移除闭包，避免取消或保存失败造成文件误删；删除 Others 或不存在的 Topic 时返回现有风格的可测试错误。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/TopicServiceTests`

Expected: PASS with cascade, error and audio cleanup assertions.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Library/TopicService.swift InterviewFlashcard/Features/Trash/TrashService.swift InterviewFlashcardTests/TopicServiceTests.swift InterviewFlashcardTests/TrashServiceTests.swift
git commit -m "feat: support destructive topic deletion"
```

### Task 4: 移除新的语音回答/转写运行时链路

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerSubmissionService.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/App/InterviewFlashcard-Info.plist`
- Modify: `InterviewFlashcardTests/AnswerSubmissionServiceTests.swift`
- Modify: `InterviewFlashcardTests/AnswerEditorTests.swift`
- Modify: `InterviewFlashcardTests/AppShellTests.swift`
- Delete: `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`
- Delete: `InterviewFlashcard/Core/Speech/SpeechTranscribing.swift`
- Delete: `InterviewFlashcard/Core/Speech/AppleSpeechTranscriber.swift`
- Delete: `InterviewFlashcard/Core/Speech/AudioRecording.swift`
- Delete: `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`
- Delete: `InterviewFlashcardTests/SpeechCapabilityTests.swift`

**Interfaces:**
- Consumes the existing `AnswerSubmissionService.submitText(questionID:rawText:context:)` path.
- Preserves `AnswerInputMode.voice`, `AudioAssetRecord`, old history display and trash cleanup as persisted-data compatibility only.
- Removes `AnswerSubmissionService.AudioAssetDraft`, `submitVoice`, `SubmissionError.missingAudioAsset`, speech launch arguments, speech dependencies and permission declarations.

- [ ] **Step 1: 写失败测试**

更新文字提交测试，断言文字提交创建 typed attempt 且不创建 AudioAssetRecord；更新 AnswerEditor 测试/可访问性断言，要求回答视图不存在 voice identifier，不读取 speech capability；更新 AppShell 测试，要求启动参数不再解析 `-IFSpeechCapability`。

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/AnswerSubmissionServiceTests -only-testing:InterviewFlashcardTests/AnswerEditorTests -only-testing:InterviewFlashcardTests/AppShellTests`

Expected: FAIL until the UI and environment no longer expose voice capability state.

- [ ] **Step 3: 删除生产语音入口并保留历史兼容**

从 AnswerEditor 移除语音状态、能力检查、voiceEntry 和 voice submit 分支；AnswerSubmissionService 只保留文字提交；从 AppEnvironment 移除语音依赖和 launch override；删除权限声明和不再引用的录音/转写源文件。不要删除 AnswerInputMode.voice、AudioAssetRecord 或历史视图读取逻辑，以保证旧 store 可读。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/AnswerSubmissionServiceTests -only-testing:InterviewFlashcardTests/AnswerEditorTests -only-testing:InterviewFlashcardTests/AppShellTests`

Expected: PASS; all normal answer submission tests remain green and no speech sources are compiled.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Practice/AnswerEditorView.swift InterviewFlashcard/Features/Practice/AnswerSubmissionService.swift InterviewFlashcard/App/AppEnvironment.swift InterviewFlashcard/App/InterviewFlashcard-Info.plist InterviewFlashcardTests/AnswerSubmissionServiceTests.swift InterviewFlashcardTests/AnswerEditorTests.swift InterviewFlashcardTests/AppShellTests.swift InterviewFlashcard/Features/Practice/VoiceAnswerView.swift InterviewFlashcard/Core/Speech/SpeechTranscribing.swift InterviewFlashcard/Core/Speech/AppleSpeechTranscriber.swift InterviewFlashcard/Core/Speech/AudioRecording.swift InterviewFlashcardTests/VoiceAnswerFlowTests.swift InterviewFlashcardTests/SpeechCapabilityTests.swift
git commit -m "refactor: remove voice answering flow"
```

### Task 5: 完成回答页标题和文字回答视觉收口

**Files:**
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerComposerView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift`
- Test: `InterviewFlashcardTests/AnswerEditorTests.swift`

**Interfaces:**
- Card-back presentation displays no navigation title text; standalone answer presentation displays “回答”。
- Text composer remains the only answer input and uses existing submit/result callbacks.

- [ ] **Step 1: 写失败测试**

为 AnswerEditor 的 presentation behavior 增加测试/可访问性检查：card-back 不暴露“练习”标题，题目、文字编辑器、提交按钮、处理状态和结果 identifier 仍存在；普通 screen 模式仍有“回答”标题语义。

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/AnswerEditorTests`

Expected: FAIL while card-back still sets the “练习” navigation title.

- [ ] **Step 3: 调整标题和编辑器布局**

让导航标题只由 presentation 决定，card-back 使用空标题但保留返回层级；清理语音删除后产生的多余间距，确保文字编辑器、提交按钮和评分状态在同一滚动内容中保持清晰边界。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/AnswerEditorTests`

Expected: PASS with no “练习” title and a functional text-only answer editor.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Practice/AnswerEditorView.swift InterviewFlashcard/Features/Practice/AnswerComposerView.swift InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift InterviewFlashcardTests/AnswerEditorTests.swift
git commit -m "ui: simplify text answer screen"
```

### Task 6: 重做题库列表、编号排序和题目多选交互

**Files:**
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift`
- Create: `InterviewFlashcard/Features/Library/LibraryQuestionOrdering.swift`
- Create: `InterviewFlashcardTests/LibraryQuestionOrderingTests.swift`

**Interfaces:**
- Produces `LibraryQuestionOrdering.newestFirst(_:_:)` using non-nil `questionNumber` descending, with `createdAt`/UUID fallback only for the migration window.
- `LibraryView` keeps question selection state but removes all Topic selection state and toolbar selection-mode buttons.
- Topic row exposes a trailing swipe delete action that opens the destructive confirmation dialog from `LibraryView`.

- [ ] **Step 1: 写失败测试**

在 `LibraryQuestionOrderingTests` 中构造编号 8、3、11 的题目，断言顺序为 11、8、3；构造 nil 编号题目验证稳定 fallback；断言相同编号不会导致随机顺序。为 TopicService/UI-facing state 增加测试数据，确认 Others 不提供可删除资格由 Task 3 的服务测试保证。

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodegen generate && DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/LibraryQuestionOrderingTests`

Expected: FAIL because the ordering helper does not exist.

- [ ] **Step 3: 实现题库布局与交互**

在 Topics section header 右侧放新建 Topic 加号；移除工具栏中的“完成/选择题目/选择 Topic”按钮、Topic 选择圆圈和 Topic 批量删除底栏；题目和 Topic 行使用统一圆角背景与细边框。题目行显示编号和单行题干，并按编号降序；搜索结果复用同一行视觉。保留长按进入题目多选、底部全选/移动/退出操作；给列表的非题目区域添加退出多选行为。为普通 Topic 添加 `swipeActions(edge: .trailing, allowsFullSwipe: false)`，触发 impact 后显示名称、题目数量和不可撤销说明的确认弹窗；确认调用 Task 3 的永久删除接口，取消只清空待删除状态。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/LibraryQuestionOrderingTests -only-testing:InterviewFlashcardTests/TopicServiceTests`

Expected: PASS; ordering and deletion service behavior are green. UI gesture details will be checked in Task 8.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Library/LibraryView.swift InterviewFlashcard/Features/Library/LibraryQuestionOrdering.swift InterviewFlashcardTests/LibraryQuestionOrderingTests.swift
git commit -m "ui: redesign library topic and question interactions"
```

### Task 7: 重做设置根页与 AI/练习子页排版

**Files:**
- Modify: `InterviewFlashcard/Features/Settings/SettingsView.swift`
- Modify: `InterviewFlashcard/Features/Settings/AIServiceSettingsView.swift`
- Modify: `InterviewFlashcard/Features/Settings/PracticeSettingsView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`
- Modify: `InterviewFlashcardTests/AppShellTests.swift`

**Interfaces:**
- Root `SettingsView` presents `NavigationLink` rows for `AIServiceSettingsView` and `PracticeSettingsView`, plus a static privacy card; it no longer embeds `AIServiceSettingsContent` or `PracticeSettingsContent` inside DisclosureGroups.
- AI child view groups controls under service provider, connection, actions and security note sections.
- Practice child view groups topic toggles, practiced-question scope and explanatory copy under system List sections.
- Produces `AccessibilityID.settingsAIServiceRow` and `AccessibilityID.settingsPracticeRow` for the two root navigation rows.
- Existing persistence methods (`saveAIConfiguration`, `testAIConnection`, `setPracticeTopicIDs`, `setIncludePracticed`) remain the only mutation APIs.

- [ ] **Step 1: 写失败测试**

先在 `AppShellTests` 中引用计划中的 `AccessibilityID.settingsAIServiceRow` 和 `AccessibilityID.settingsPracticeRow`，断言它们与现有 AI/练习子页 identifier 不重复；此时常量尚未添加，测试应先因编译失败，纯数据/校验契约仍由 `AISettingsDraftTests` 和 `PracticeSettingsStoreTests` 覆盖，模拟器页面结构在 Task 8 验收。

- [ ] **Step 2: 运行测试确认失败**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/AppShellTests -only-testing:InterviewFlashcardTests/AISettingsDraftTests -only-testing:InterviewFlashcardTests/PracticeSettingsStoreTests`

Expected: Existing UI/summary assertions either fail on removed DisclosureGroup identifiers or expose missing root navigation identifiers, while pure settings draft/store tests remain green.

- [ ] **Step 3: 实现分组导航布局**

将根页改为系统 List 分组导航，使用语义色、SF Symbols、Dynamic Type 和独立说明卡；AI 页把输入与操作分段，测试中状态只显示在操作段；练习页把主题开关、题目范围和说明分段，保持主题数量摘要与现有持久化行为一致。不要在根页重复渲染完整子表单。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -only-testing:InterviewFlashcardTests/AppShellTests -only-testing:InterviewFlashcardTests/AISettingsDraftTests -only-testing:InterviewFlashcardTests/PracticeSettingsStoreTests`

Expected: PASS with settings storage/validation preserved and all new navigation/accessibility identifiers present.

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Settings/SettingsView.swift InterviewFlashcard/Features/Settings/AIServiceSettingsView.swift InterviewFlashcard/Features/Settings/PracticeSettingsView.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/AppShellTests.swift
git commit -m "ui: reorganize settings screens"
```

### Task 8: 全量测试、构建和模拟器实际操作验收

**Files:**
- Create: `docs/acceptance/2026-08-14-library-practice-settings.md` with commands, screenshots and results.
- Create: `diagnostics/acceptance/library-practice-settings-20260814/` artifacts generated by acceptance scripts.

**Interfaces:**
- Consumes all completed tasks and their accessibility identifiers.
- Produces a full XCTest result, a successful Debug build and screenshots/video proving the six required UI paths.

- [ ] **Step 1: Regenerate the Xcode project**

Run: `xcodegen generate`

Expected: `InterviewFlashcard.xcodeproj` includes every new Swift file and excludes every deleted speech file without unrelated project changes.

- [ ] **Step 2: Run the complete test suite**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' | tee diagnostics/acceptance/library-practice-settings-20260814/tests.log`

Expected: `** TEST SUCCEEDED **`, with no test failures and no compile references to deleted speech files.

- [ ] **Step 3: Build the app with diagnostics enabled**

Run: `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild build -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' | tee diagnostics/acceptance/library-practice-settings-20260814/build.log`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run simulator visual acceptance**

Launch the seeded simulator fixture with the existing diagnostics/acceptance tooling and inspect the app through Mac Computer Use. Verify: Topics header plus position; no selection toolbar buttons; numbered cards with descending order and visible borders; long-press selection; tap-outside exit; question batch move dropdown; Topic swipe confirmation/cancel/confirm cascade; text-only answer page with no “练习” title or voice card; and the reorganized root/child settings pages. Capture top/bottom screenshots and a short walkthrough video in the dated diagnostics directory.

- [ ] **Step 5: Verify data invariants after UI actions**

Export the diagnostic state after moving questions and deleting a disposable Topic. Confirm moved cards retain their numbers, deleted Topic cards and dependent records are absent, and old voice compatibility records remain readable in the history fixture.

- [ ] **Step 6: Record acceptance and commit artifacts**

Write the simulator name, build/test commands, observed UI results, artifact paths and any known beta-only limitations into `docs/acceptance/2026-08-14-library-practice-settings.md`. Commit only that note and the generated artifacts that belong to this task.

```bash
git add docs/acceptance/ diagnostics/acceptance/library-practice-settings-20260814
git commit -m "test: verify library practice settings redesign"
```

## Self-Review Checklist

- [ ] Every requirement in `docs/superpowers/specs/2026-08-14-library-practice-settings-redesign-design.md` maps to Tasks 1–8.
- [ ] The plan never removes legacy voice persistence fields or old history readability.
- [ ] `questionNumber` is consistently named across model, service, import, manual creation, ordering and tests.
- [ ] Topic permanent deletion is separate from the existing move-cards deletion API.
- [ ] No task relies on a new package or an unspecified external service.
- [ ] No production or test implementation body is embedded in this plan.
