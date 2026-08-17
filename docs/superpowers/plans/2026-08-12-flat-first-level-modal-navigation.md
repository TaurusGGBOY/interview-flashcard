# Flat First-Level Modal Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将应用的功能页面压平为五个一级 Tab；练习回答、题库导入/手动添加、题目详情、回答历史和设置子项全部以内嵌展开或浮层完成，不再通过二级 `NavigationLink` 推进，同时保留现有真实 SwiftData、AI 评分和后台导入链路。

**Architecture:** 保留 `RootTabView` 作为唯一的 Tab 容器，并保留每个 Tab 的根 `NavigationStack` 仅用于标题和系统工具栏。功能之间改用局部状态驱动的 `sheet` / `sheet(item:)`；练习页在同一张卡片中切换题目正面和回答背面，回答结果作为可关闭的评分浮层。将设置页面的可复用表单内容抽成内嵌组件，避免在 `SettingsView` 中嵌套 `Form` 或再创建导航栈。为 Topic 批量删除补充服务层原子操作，UI 只负责选择和确认。

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 26, XcodeGen, XCTest, iOS Simulator。

## Review Findings and Optimization Decisions

- 当前页面层级问题集中在 `PracticeView`、`LibraryView`、`ImportView`、`QuestionDetailView`、`HistoryView`、`HistoryQuery`、`SettingsView` 中的 `NavigationLink`，评分和导入业务服务不需要重写。
- `RootTabView` 的五个一级入口及现有 accessibility identifier 保持不变；只移除子页面 push 路由，避免破坏已有 Tab 和空状态跳转测试。
- 评分结果复用现有 `AnswerEditorView`、`AnswerProcessingService` 和 `EvaluationResultView`。提交后先展示已有的分数/小分状态，评语和满分答案继续在同一个结果浮层中分阶段更新；关闭浮层不会取消已经提交的真实评分任务。
- 练习页不复制回答提交逻辑：通过回答编辑器的 presentation mode 和回调，把编辑器嵌进卡片背面；提交后卡片继续保留，左下角返回正面，右下角打开该题历史，评分浮层可随时关闭。
- 题库使用 inline `DisclosureGroup` 展开 Topic，题目用 `Button` 打开详情浮层；导入和手动添加也由库页面直接弹 sheet。Topic 多选删除下沉到 `TopicService`，一次保存并统一移动题目到目标 Topic。
- 设置页面抽出 AI 和练习设置的内容组件，用 `DisclosureGroup` 在同一页面展开；安全与隐私说明也作为可展开项，避免 `NavigationLink` 和嵌套 `Form`。
- 不引入 fake/stub 数据或替换 AI client。模拟器验证使用当前持久化的真实数据；若需要 UI 测试，测试目标只驱动真实应用状态，不注入 stub 服务。

## Implementation Steps

### 1. Establish modal presentation state and preserve root contracts

- [ ] 保持 `AppRoute.rootTabs`、`RootTabView` 的五个 Tab 和根 accessibility identifiers 不变；为导入、手动题目、题目详情、历史详情、回收站、Others、评分结果定义一致的 sheet presentation 入口。
- [ ] 为新增的正面/背面、返回题目、查看历史、各类浮层补充稳定 accessibility identifiers，并保留现有测试使用的 identifiers。
- [ ] 清理功能页面中不再需要的 `navigationDestination`，确保产品 Feature 源码中不残留会制造二级页面的 `NavigationLink`；根 Tab 的 `NavigationStack` 和系统文件选择器除外。

**Files:** `InterviewFlashcard/App/RootTabView.swift`, `InterviewFlashcard/Shared/AppRoute.swift`, `InterviewFlashcard/Features/*` accessibility declarations, existing shell tests.

**Tests:** 保留并运行现有 AppShell/Tab 测试；增加静态检查，确认 Feature 页面没有遗留子页面 push 路由。

### 2. Implement card flip and staged evaluation sheet in Practice

- [ ] 给 `PracticeFeedView` 增加“回答中/卡片背面”状态和 3D flip transition；正面仍支持点击开始回答、右划回答、左划跳过。
- [ ] 将 `AnswerEditorView` 拆出可复用的内容/展示模式：根页面模式继续支持完整编辑体验，卡片背面模式不改变提交、语音转写、失败重试和真实评分服务，只改变外壳布局。
- [ ] 提交后不再通过 `navigationDestination` 离开练习页；结果由 `AnswerEditorView` 以可关闭 sheet 展示。保留当前分数先到、评语后到、满分答案最后到的状态更新，让结果页逐段刷新。
- [ ] `EvaluationResultView` 增加可选关闭回调和 sheet-safe 的回答历史入口；关闭只关闭浮层，继续答题才结束当前卡片并抽取下一题。
- [ ] 在回答背面提供左下角“返回题目”和右下角“查看历史”，并使左右滑动分别执行同样动作；无提交时返回不会丢失草稿，已提交时仍可从结果浮层进入历史。

**Files:** `InterviewFlashcard/Features/Practice/PracticeView.swift`, `PracticeFeedView.swift`, `PracticeSwipeActionLayer.swift`, `AnswerEditorView.swift`, `AnswerComposerView.swift`, `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`, new small presentation helper if needed.

**Tests:** 扩展练习纯状态/手势映射测试，覆盖正面和背面的左右动作；增加评分结果 sheet 可关闭、继续答题和历史入口的 view/state contract tests；保留现有真实提交服务测试。

### 3. Flatten Library, import, manual entry, and Topic management

- [ ] 将库页面的“导入文本文件”和“手动添加题目”改成直接弹 sheet；保留 Markdown file importer、后台导入进度、失败重试、整理结果和一键确认语义。
- [ ] 将 `ImportView` 内的“查看整理结果/查看生成题目”改成 sheet 状态，不再用 `NavigationLink`；生成题目列表中点题目再弹 `QuestionDetailView`。
- [ ] 将 Topic 列表改为 `DisclosureGroup`/等价 inline 展开：点击 Topic 展开题目，点击题目弹详情 sheet；保留 Others 的重新分类能力，但从 sheet 打开。
- [ ] 增加 Topic 多选模式、全选/取消选择、删除确认和目标 Topic 选择；Others 不能被选中删除。保留单 Topic 重命名和已有的题目多选删除。
- [ ] 为 `TopicService` 增加批量删除 API：校验所有源 Topic、目标 Topic 和系统 Topic 约束，先移动全部卡片，再删除源 Topic，最后一次保存；让现有单 Topic API 复用同一实现。
- [ ] 将题目详情内部的“开始回答”和回答历史改成 sheet，避免从题目详情继续 push；回收站也从库页面以 sheet 打开。

**Files:** `InterviewFlashcard/Features/Library/LibraryView.swift`, `QuestionDetailView.swift`, `TopicEditorView.swift`, `InterviewFlashcard/Features/Import/ImportView.swift`, `InterviewFlashcard/Features/Trash/TrashView.swift`, `InterviewFlashcard/Features/Reclassification/OthersView.swift`, `InterviewFlashcard/Core/Services/TopicService.swift`, `InterviewFlashcardTests/TopicServiceTests.swift` and related import/library tests.

**Tests:** 新增批量删除成功、目标在选中集合中、包含 Others、目标不存在等 service tests；覆盖导入和手动添加 sheet 的状态入口；导入仍使用真实 Markdown/真实 AI pipeline，不写入假题目。

### 4. Flatten History and Settings

- [ ] `HistoryView` 的回答行改为 Button + `sheet(item:)` 展示 `AttemptDetailView`；`QuestionHistoryView` 同样改为 sheet，保留筛选、搜索和处理状态。
- [ ] 保持 `AttemptDetailView` 为可复用详情内容，但移除继续 push 的依赖并补上 sheet 标题/关闭行为。
- [ ] 抽出 `PracticeSettingsContent`，让旧的 `PracticeSettingsView` 作为兼容 wrapper，`SettingsView` 用 `DisclosureGroup` 内嵌它；保留主题选择、全选、题目范围和实时 reconciliation。
- [ ] 抽出 `AIServiceSettingsContent`，让旧的 `AIServiceSettingsView` 作为兼容 wrapper，`SettingsView` 内嵌它；保留 provider、Base URL、model、Keychain、连接测试和保存行为。
- [ ] 将安全与隐私说明也做成可展开设置项，并保证设置页本身不再有二级 `NavigationLink`。

**Files:** `InterviewFlashcard/Features/History/HistoryView.swift`, `HistoryQuery.swift`, `InterviewFlashcard/Features/Settings/SettingsView.swift`, `PracticeSettingsView.swift`, `AIServiceSettingsView.swift` and related settings/history tests.

**Tests:** 保留 AI draft/configuration 与练习设置的现有单元测试；增加 sheet selection 和 DisclosureGroup 展开契约测试，检查设置保存逻辑没有被展示层重构改变。

### 5. Verify build, real data behavior, and simulator interaction

- [ ] 运行 `xcodegen generate`，确认新文件/项目引用正确。
- [ ] 运行 InterviewFlashcardTests 全量测试，再运行 app build；失败时按测试失败根因修复，不通过跳过或注入 stub。
- [ ] 在可用 iOS Simulator 上安装并启动真实构建，检查：练习卡正反面、真实回答提交、分阶段评分浮层、历史浮层、库 Topic 展开/多选删除、真实 Markdown 导入、手动添加、题目详情浮层、历史详情浮层、设置 DisclosureGroup。
- [ ] 用 `rg` 复查产品 Feature 源码的 push 导航残留，只允许根 Tab `NavigationStack`、必要的 preview 包装和系统 file importer；确认无 fake/stub 数据代码进入生产路径。
- [ ] 汇总测试命令、构建结果、模拟器验证结果和仍需人工确认的外部 AI 网络条件。

**Verification commands:**

```sh
DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' \
  xcodegen generate

DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' \
  xcodebuild -quiet -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' test

DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' \
  xcodebuild -quiet -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' build
```

## Risks and Mitigations

- SwiftUI sheet 中直接持有 SwiftData model 可能在删除或刷新后失效：所有 sheet selection 在删除、保存和 dismiss 时清空，并优先用稳定 UUID 绑定必要状态。
- 卡片背面嵌入编辑器可能与水平手势冲突：让外层 swipe layer 只处理水平位移，编辑器内部继续处理垂直滚动，并用纯手势映射测试覆盖阈值。
- staged evaluation 可能在 sheet 关闭后仍更新：评分任务继续由现有服务管理，视图只在仍挂载时刷新；关闭时不删除 EvaluationRecord。
- Topic 批量删除必须避免级联误删：服务层先验证所有关系和目标，再移动卡片并单次保存；测试覆盖系统 Topic 和目标冲突。
- 不为了模拟器验证改变生产依赖注入：没有真实 AI 网络时只报告外部条件，不使用 stub 冒充成功。
