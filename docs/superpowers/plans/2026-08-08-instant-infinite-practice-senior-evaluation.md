# InterviewFlashcard 启动即刷题、无限卡片与资深级评分 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 InterviewFlashcard 重构为针对 iPhone 17 Pro Max 的“打开即练”体验：冷启动直接展示一张可左右滑动的彩色题卡，左滑跳过、右滑进入回答；题目持续随机补充，不再有 5/10/20 道的练习批次；评分页先展示六维雷达图，再展示与本题和本次回答直接相关的详细评价，并保证新导入题目的满分答案达到高级软件工程师面试标准。

**Architecture:** 用一个无终点的 `PracticeFeedState` 替换现有 `scope → session → complete` 状态机，但继续复用现有随机抽题、滑动手势、回答、历史和回收站能力。主题和“包含练习过的题”降级为练习页上的过滤入口，配置只影响当前运行中的抽题池。AI 仍保持“原始回答直接一次评分、零润色请求”，将更严格的资深级评分要求放进提示词和响应校验；详细证据以版本化 JSON 存入现有 `feedbackJSON`，避免 SwiftData 迁移。六维雷达图用原生 SwiftUI 绘制。App Icon 使用 image2 产出原创资源并由 Asset Catalog 管理。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、Swift Testing、XcodeGen、DeepSeek Chat Completions API、原生 `Canvas/Path`、Computer Use、iPhone 17 Pro Max 模拟器（iOS 27.0）。

## Global Constraints

- 唯一验收设备为 `iPhone 17 Pro Max`，UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`，iOS 27.0；不为其他模拟器补做专项验收。
- App 只支持竖屏；冷启动和从主屏幕再次启动都必须保持竖屏且铺满安全区，不出现上下大块黑边。
- 冷启动直接进入练习 Tab 并立即显示题目；不得出现主题选择页、题量选择器、“开始练习”按钮或完成页。
- 不再有 5/10/20 道一组、目标题数或练习结束概念。只要过滤后的题池不为空，就始终维持一张当前卡。
- 冷启动默认选中全部可用主题；“包含已经练习过的题”默认关闭。配置是练习页的次级入口，不持久化，App 重启后恢复默认值。
- 抽题保持纯随机。左滑仅记“跳过”，不创建回答记录，也不永久排除该题；同一题之后可以再次被抽到。题库只有一题时，左滑后仍应回到这一题。
- 右滑翻面并进入回答界面；满分答案只能在提交后于评分结果中出现，题卡正面和回答输入阶段都不得显示。
- 主卡片应尽量利用可用屏幕，问题文字水平居中；短题在视觉上居中，长题允许滚动且不得截断。卡片配色由题目稳定派生，需兼顾深浅色、动态字体和对比度。
- 语音按钮仅在本地转写能力可用时启用；本地转写不可用时不得提供可点击的语音入口。此计划不新增云端语音转写。
- 每次回答只发起一次真实 DeepSeek 评分请求；不得先润色，不得发送第二次评分请求。提示词明确输入可能来自语音转文字或输入法转录，允许措辞噪声，但不得替用户补充缺失知识。
- 固定六维评分及权重：正确性 35、覆盖度 25、推理深度 15、表达结构 10、权衡意识 10、术语精确性 5，总分 100。
- 评分页首屏先展示总分与六维雷达图；详细评价位于其下。评价必须引用本次回答中的具体内容，指出本题缺失点，并与满分答案的关键点对应，禁止泛泛模板话术。
- 新导入或重新生成的满分答案必须符合高级软件工程师面试标准：有明确结论、关键机制、边界/失败场景、工程权衡和可追问细节，不能用一两句话通过校验。
- 不新增 SwiftData schema 版本；结构化评分明细写入现有 `EvaluationRecord.feedbackJSON`，关键点写入现有 `ReferenceAnswerVersionRecord.keyPointsJSON`。
- 保留现有 Markdown 分批导入、50 题一批的 AI 润色/去重、并发控制、回答历史、统计、回收站和删除确认行为。
- 每个用户可见任务完成后都要使用 Computer Use 在指定模拟器验收，并把截图、日志和状态快照按计划中的固定文件名写入 `diagnostics/acceptance/instant-practice-senior-evaluation/`。
- 当前工作树已有大量未提交改动。每个任务只暂存该任务列出的文件；提交前运行 `git diff --check`，不得覆盖、回滚或顺手整理用户的其他改动。

---

## File Map

| 路径 | 变更 | 职责 |
|---|---|---|
| `InterviewFlashcard/Features/Practice/PracticeFeedState.swift` | 新建 | 无终点题卡流的纯状态机：当前题、过滤、跳过、回答后补卡、撤销与空池状态 |
| `InterviewFlashcard/Features/Practice/PracticeFilterSheet.swift` | 新建 | 主题和“包含练习过的题”的次级配置面板 |
| `InterviewFlashcard/Features/Practice/PracticeFeedView.swift` | 新建 | 练习页主体、卡片堆叠、顶部轻量入口、空状态和滑动编排 |
| `InterviewFlashcard/Features/Practice/QuestionCardTheme.swift` | 新建 | 根据稳定题目 UUID 生成可复现的渐变、前景色和装饰参数 |
| `InterviewFlashcard/Features/Practice/PracticeView.swift` | 修改 | 启动即创建 feed，移除 scope/session/complete 分支并协调抽题 |
| `InterviewFlashcard/Features/Practice/AnswerEditorView.swift` | 修改 | 明确提交回调传递 `questionID`，而不是 `attemptID` |
| `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift` | 修改 | 为卡片、过滤入口、空状态、雷达图与详情增加稳定标识 |
| `InterviewFlashcard/App/RootTabView.swift` | 修改 | 保持练习为默认 Tab，并允许全局空状态跳转题库 |
| `InterviewFlashcard/Features/Practice/PracticeScopeView.swift` | 删除 | 删除启动前配置页 |
| `InterviewFlashcard/Features/Practice/PracticeSessionView.swift` | 删除 | 删除有限题量会话壳层 |
| `InterviewFlashcard/Features/Practice/PracticeSessionCompleteView.swift` | 删除 | 删除完成页 |
| `InterviewFlashcard/Features/Practice/PracticeSessionState.swift` | 删除 | 删除目标题数与完成原因状态 |
| `InterviewFlashcard/Features/Practice/QuestionCardView.swift` | 修改 | 大尺寸彩色题卡、居中排版、长文本滚动、无障碍 |
| `InterviewFlashcard/Features/Practice/PracticeSwipeActionLayer.swift` | 修改 | 适配大卡片并保留左跳过/右回答手势和按钮等价操作 |
| `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift` | 修改 | 明确跳过题可重入随机池和单题循环规则 |
| `InterviewFlashcard/Features/Evaluation/EvaluationDetailPayload.swift` | 新建 | 版本化评分详情 JSON 及旧数据兼容解码 |
| `InterviewFlashcard/Features/Evaluation/RadarChartLayout.swift` | 新建 | 六轴点位、归一化和标签布局的纯计算 |
| `InterviewFlashcard/Features/Evaluation/ScoreRadarChart.swift` | 新建 | 原生 SwiftUI 六维雷达图 |
| `InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift` | 修改 | 从新旧 `feedbackJSON` 统一生成展示模型 |
| `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift` | 修改 | 总分与雷达图优先，题目相关详情随后 |
| `InterviewFlashcard/Core/AI/AISchemas.swift` | 修改 | 收紧评分类响应校验与版本元数据要求 |
| `InterviewFlashcard/Core/AI/PromptCatalog.swift` | 修改 | 新增资深满分答案和直接评分提示词版本 |
| `InterviewFlashcard/Core/AI/DeepSeekAIClient.swift` | 修改 | 使用请求端权威 rubric 元数据并维持单请求评分 |
| `InterviewFlashcard/Features/Practice/AnswerProcessingService.swift` | 修改 | 将完整评分证据编码到现有字段，保持 raw == polished 兼容语义 |
| `InterviewFlashcard/Features/Import/FullScoreAnswerQualityPolicy.swift` | 新建 | 满分答案格式、长度和关键点质量门禁 |
| `InterviewFlashcard/Features/Import/ImportCoordinator.swift` | 修改 | stage 整批预检、activate 二次校验并保存关键点 |
| `InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift` | 修改 | 提供真实技术题与资深级满分答案，不预置假评分 |
| `InterviewFlashcardTests/PracticeFeedStateTests.swift` | 新建 | 无限流状态机测试 |
| `InterviewFlashcardTests/PracticeFilterSheetTests.swift` | 新建 | 默认过滤与空池判定测试 |
| `InterviewFlashcardTests/QuestionCardThemeTests.swift` | 新建 | 稳定配色与对比度测试 |
| `InterviewFlashcardTests/RadarChartLayoutTests.swift` | 新建 | 六轴几何、边界值和顺序测试 |
| `InterviewFlashcardTests/EvaluationDetailPayloadTests.swift` | 新建 | v2 编解码与旧格式回退测试 |
| `InterviewFlashcardTests/FullScoreAnswerQualityPolicyTests.swift` | 新建 | 资深答案质量门禁测试 |
| `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift` | 修改 | 跳过可重入与单题循环测试 |
| `InterviewFlashcardTests/AnswerProcessingServiceTests.swift` | 修改 | 一次评分、零润色、结构化详情持久化测试 |
| `InterviewFlashcardTests/AIResponseValidatorTests.swift` | 修改 | 证据、缺失点和版本一致性测试 |
| `InterviewFlashcardTests/ImportCoordinatorTests.swift` | 修改 | 整批拒绝、无部分写入和关键点保存测试 |
| `InterviewFlashcardTests/EvaluationPresentationTests.swift` | 修改 | 雷达数据、新详情与旧记录兼容测试 |
| `InterviewFlashcardTests/AppShellTests.swift` | 修改 | 默认练习 Tab、竖屏和直接题卡入口测试 |
| `InterviewFlashcardTests/Support/Fixtures.swift` | 修改 | 提供合格资深答案和具体评分 fixtures |
| `InterviewFlashcardTests/TestHost/TestHostApp.swift` | 修改 | UI 测试宿主展示直接题卡与雷达结果 |
| `InterviewFlashcard/Resources/Assets.xcassets/Contents.json` | 新建 | Asset Catalog 根清单 |
| `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | 新建 | App Icon 的 universal/light/dark/tinted 槽位清单 |
| `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | 新建 | image2 生成的 light 1024×1024 App Icon |
| `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png` | 新建 | image2 生成的 dark 1024×1024 App Icon |
| `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png` | 新建 | image2 生成的 tinted 1024×1024 App Icon |
| `project.yml` | 修改 | 纳入资源目录并设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` |
| `scripts/acceptance/assert-iphone-app-metadata.sh` | 修改 | 校验图标编译、竖屏声明和目标设备族 |
| `scripts/acceptance/run-final-checks.sh` | 修改 | 串联生成工程、全量测试、metadata 和证据完整性检查 |
| `docs/acceptance/computer-use-runbook.md` | 修改 | 记录直接题卡、过滤、雷达图和真 DeepSeek 验收流程 |
| `diagnostics/acceptance/instant-practice-senior-evaluation/*` | 新建 | 按 Task 8 精确清单保存截图、状态、去敏日志和演示视频 |

### Task 1: 建立无终点题卡流状态机

**Files:**
- Create: `InterviewFlashcard/Features/Practice/PracticeFeedState.swift`
- Create: `InterviewFlashcardTests/PracticeFeedStateTests.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift`
- Modify: `InterviewFlashcardTests/PracticeSwipeInteractionTests.swift`

**Interfaces:**
- Consumes: `QuestionDrawService.eligibleQuestions(...)` 的现有候选题集合，以及 `PracticeSwipeInteraction.nextDrawPool(...)` 的随机池逻辑。
- Produces: `PracticeFeedState`，包含 `currentQuestionID: UUID?`、`selectedTopicIDs: Set<UUID>`、`includePracticed: Bool`、`emptyReason(totalActiveCount:eligibleCount:)`、`present(questionID:)`、`skipCurrent()`、`answerCurrent()` 和 `undoLastSwipe()`，供 Task 2 的练习容器使用。

- [ ] **Step 1: Write the failing tests**

在 `PracticeFeedStateTests` 覆盖以下行为：

- 初始化没有目标题数、计数上限或完成状态。
- `present(questionID:)` 设置当前题；`skipCurrent()` 清空当前题并记录本次跳过，但不永久排除该题。
- `answerCurrent()` 清空当前题，且让默认关闭的“包含已练习”过滤依赖持久化回答状态排除它。
- 多题时下一抽避免立即重复当前题；之后允许被跳过题再次出现。
- 只有一题时，左滑后下一抽仍返回同一题。
- 抽题池变空时返回可区分的 `globalLibraryEmpty` 或 `filteredPoolEmpty`，不返回 `sessionComplete`。
- 撤销只恢复最近一次滑动及其当前题，不删除已经持久化的回答。

同时在 `PracticeSwipeInteractionTests` 增加“跳过题可重入池”和“单题池不死锁”的纯函数测试。

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/PracticeFeedStateTests \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests
```

Expected: FAIL because `PracticeFeedState` and the new infinite-pool API do not exist.

- [ ] **Step 3: Write the minimal implementation**

新增纯值类型 `PracticeFeedState`，接口至少包括：

- `currentQuestionID: UUID?`
- `selectedTopicIDs: Set<UUID>`
- `includePracticed: Bool`，默认 `false`
- `lastAction`，只保存当前可撤销动作
- `emptyReason(totalActiveCount:eligibleCount:)`
- `present(questionID:)`、`skipCurrent()`、`answerCurrent()`、`undoLastSwipe()`

调整 `PracticeSwipeInteraction.nextDrawPool`：只在候选数大于一时排除刚离开的题；候选只有一题时返回它。不要维护“本会话已展示 ID 集合”，因为它会把有限会话语义重新带回来。

- [ ] **Step 4: Run tests to verify they pass**

重复 Step 2 命令。

Expected: PASS；测试中不存在目标题数、完成原因或批次结束断言。

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Practice/PracticeFeedState.swift \
  InterviewFlashcard/Features/Practice/PracticeSwipeInteraction.swift \
  InterviewFlashcardTests/PracticeFeedStateTests.swift \
  InterviewFlashcardTests/PracticeSwipeInteractionTests.swift
git diff --cached --check
git commit -m "feat: add infinite practice feed state"
```

### Task 2: 冷启动直接进入题卡，并把配置降级为过滤面板

**Files:**
- Create: `InterviewFlashcard/Features/Practice/PracticeFilterSheet.swift`
- Create: `InterviewFlashcard/Features/Practice/PracticeFeedView.swift`
- Create: `InterviewFlashcardTests/PracticeFilterSheetTests.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift`
- Modify: `InterviewFlashcard/App/RootTabView.swift`
- Modify: `InterviewFlashcardTests/AppShellTests.swift`
- Modify: `InterviewFlashcardTests/TestHost/TestHostApp.swift`
- Delete: `InterviewFlashcard/Features/Practice/PracticeScopeView.swift`
- Delete: `InterviewFlashcard/Features/Practice/PracticeSessionView.swift`
- Delete: `InterviewFlashcard/Features/Practice/PracticeSessionCompleteView.swift`
- Delete: `InterviewFlashcard/Features/Practice/PracticeSessionState.swift`
- Delete: `InterviewFlashcardTests/PracticeSessionStateTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `PracticeFeedState` 和现有 `QuestionDrawService`；`RootTabView` 提供可写的选中 Tab binding/closure。
- Produces: `PracticeFeedView`、`PracticeFilterSheet`，以及语义明确的 `AnswerEditorView.onAttemptSubmitted(questionID:)`；Task 3 在 `PracticeFeedView` 中替换题卡视觉，Task 8 依赖其 accessibility identifiers 验收。

- [ ] **Step 1: Write the failing tests**

新增或修改测试验证：

- `PracticeView` 初始模型为 feed，而不是 `scope`。
- 首次加载选中全部活跃主题，`includePracticed == false`，且无需用户点击即可发起一次随机抽题。
- 不存在题量选择和“开始练习”控件。
- 过滤面板只暴露主题多选和“包含已练习题”；应用过滤后立刻重抽，不创建练习会话。
- 所有活跃题目都不存在时显示“导入题目”动作，并通过 `RootTabView` 的 binding/closure 切换到题库 Tab。
- 仅因过滤条件为空时显示“调整筛选”，点击重新打开过滤面板。
- `AnswerEditorView` 的提交回调明确传递 `questionID`；加入回归测试，防止把 `attempt.id` 当题目 ID 导致回答后无法补卡。

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AppShellTests \
  -only-testing:InterviewFlashcardTests/PracticeFilterSheetTests
```

Expected: FAIL because the existing screen starts in `scope` and still exposes session sizes.

- [ ] **Step 3: Write the minimal implementation**

- 将 `PracticeView` 改为持有 `PracticeFeedState`，进入视图时加载活跃主题并立即调用现有 `QuestionDrawService`。
- 用 `PracticeFeedView` 组合顶部轻量过滤按钮、单张主卡、左右操作提示和空状态；不要增加新的“开始”步骤。
- `PracticeFilterSheet` 使用 sheet 呈现。取消不改状态；应用后原子替换过滤条件并重抽。
- 修改 `AnswerEditorView` 回调签名为语义明确的 `onAttemptSubmitted(questionID:)`，保存成功后传入提交题目的 ID。
- `RootTabView` 将选中 Tab 作为可写状态传入练习页，只允许全局无题的按钮切到题库。
- 删除旧有限会话视图和状态文件，并从工程生成配置中清理引用（若 XcodeGen 自动发现源文件，则只需删除文件后重新生成）。
- 给 `practice.card`、`practice.filter`、`practice.empty.library`、`practice.empty.filter` 增加稳定 accessibility identifier。

- [ ] **Step 4: Run automated verification**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AppShellTests \
  -only-testing:InterviewFlashcardTests/PracticeFilterSheetTests \
  -only-testing:InterviewFlashcardTests/PracticeFeedStateTests
```

Expected: PASS，且编译产物不再引用 `PracticeSessionState`。

- [ ] **Step 5: Verify with Computer Use**

- 构建并启动指定 iPhone 17 Pro Max。
- 终止 App 后从主屏幕再次点击图标。
- 确认启动后无需点击即看到题卡，屏幕保持竖向且上下无黑边。
- 打开过滤面板，确认没有 5/10/20 和“开始练习”。
- 保存为 `diagnostics/acceptance/instant-practice-senior-evaluation/02-cold-launch.png`、`03-filter-sheet.png` 和 `entry-state.json`。

- [ ] **Step 6: Commit**

```bash
git add -- \
  InterviewFlashcard/Features/Practice/PracticeFilterSheet.swift \
  InterviewFlashcard/Features/Practice/PracticeFeedView.swift \
  InterviewFlashcard/Features/Practice/PracticeView.swift \
  InterviewFlashcard/Features/Practice/AnswerEditorView.swift \
  InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift \
  InterviewFlashcard/Features/Practice/PracticeScopeView.swift \
  InterviewFlashcard/Features/Practice/PracticeSessionView.swift \
  InterviewFlashcard/Features/Practice/PracticeSessionCompleteView.swift \
  InterviewFlashcard/Features/Practice/PracticeSessionState.swift \
  InterviewFlashcard/App/RootTabView.swift \
  InterviewFlashcardTests/AppShellTests.swift \
  InterviewFlashcardTests/PracticeFilterSheetTests.swift \
  InterviewFlashcardTests/PracticeSessionStateTests.swift \
  InterviewFlashcardTests/TestHost/TestHostApp.swift
git diff --cached --check
git commit -m "feat: launch directly into infinite practice"
```

### Task 3: 重做大尺寸彩色题卡和滑动表现

**Files:**
- Create: `InterviewFlashcard/Features/Practice/QuestionCardTheme.swift`
- Create: `InterviewFlashcardTests/QuestionCardThemeTests.swift`
- Modify: `InterviewFlashcard/Features/Practice/QuestionCardView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeSwipeActionLayer.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeFeedView.swift`
- Modify: `InterviewFlashcardTests/TestHost/TestHostApp.swift`

**Interfaces:**
- Consumes: Task 2 的 `PracticeFeedView`、当前题目的稳定 UUID 和现有 `PracticeSwipeActionLayer` 手势状态。
- Produces: `QuestionCardTheme.theme(for questionID: UUID)` 所需的稳定主题值，以及支持短题居中、长题滚动、左跳过/右回答和按钮等价操作的 `QuestionCardView`。

- [ ] **Step 1: Write the failing tests**

在 `QuestionCardThemeTests` 验证：

- 相同 UUID 永远生成相同主题；不要使用进程间不稳定的 `hashValue`。
- 不同 UUID 能覆盖多个预定义调色板。
- 每套主题都返回明确的前景色类别，正文与背景满足至少 4.5:1 的目标对比度。
- 主题索引始终在 `0..<paletteCount` 内。

在 Test Host 增加短问题、超长问题和最大 Dynamic Type 三种场景。

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/QuestionCardThemeTests
```

Expected: FAIL because stable card theming does not exist.

- [ ] **Step 3: Write the minimal implementation**

- `QuestionCardTheme` 从 UUID 原始字节计算稳定索引，映射到一组经对比度审查的渐变和装饰。
- `QuestionCardView` 填满练习页在安全区内的主要空间，减少无信息 header；问题使用居中对齐。
- 短题在卡片可用区域视觉居中；长题放入可滚动容器，保持水平居中并保留足够上下留白。
- 左滑“跳过”和右滑“回答”叠层使用高对比度颜色、图标和文字，不能只用颜色表达。
- 保留底部可点击的跳过/回答按钮，确保不擅长手势和 VoiceOver 用户拥有等价入口。
- 卡片不得显示满分答案、评分、题量进度或“第 N/10 题”。

- [ ] **Step 4: Run automated verification**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/QuestionCardThemeTests \
  -only-testing:InterviewFlashcardTests/PracticeSwipeInteractionTests
```

Expected: PASS.

- [ ] **Step 5: Verify with Computer Use**

- 在 iPhone 17 Pro Max 上检查短题居中、大卡片占比和安全区。
- 左滑一张真实题卡，确认显示“跳过”反馈并自动补下一张。
- 右滑下一张真实题卡，确认翻面进入回答界面。
- 用超长题 fixture 和最大 Dynamic Type 确认文字可滚动、不截断。
- 保存为 `diagnostics/acceptance/instant-practice-senior-evaluation/04-left-swipe.png`、`05-right-swipe-answer.png` 和 `06-long-question.png`。

- [ ] **Step 6: Commit**

```bash
git add InterviewFlashcard/Features/Practice/QuestionCardTheme.swift \
  InterviewFlashcard/Features/Practice/QuestionCardView.swift \
  InterviewFlashcard/Features/Practice/PracticeSwipeActionLayer.swift \
  InterviewFlashcard/Features/Practice/PracticeFeedView.swift \
  InterviewFlashcardTests/QuestionCardThemeTests.swift \
  InterviewFlashcardTests/TestHost/TestHostApp.swift
git diff --cached --check
git commit -m "feat: redesign the swipe question card"
```

### Task 4: 使用 image2 制作并配置原创 App Icon

**Files:**
- Create: `InterviewFlashcard/Resources/Assets.xcassets/Contents.json`
- Create: `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Create: `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png`
- Create: `InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png`
- Modify: `project.yml`
- Modify: `scripts/acceptance/assert-iphone-app-metadata.sh`

**Interfaces:**
- Consumes: `project.yml` 的现有 app target 配置和 image2 生成的三种 1024×1024 PNG。
- Produces: 名为 `AppIcon` 的完整 Asset Catalog；`assert-iphone-app-metadata.sh [app-path]` 对图标、竖屏和 iPhone device family 返回成功或非零退出码，供 Task 8 调用。

- [ ] **Step 1: Add the failing metadata assertion**

扩展脚本，给定 `.app` 路径时检查：

- `Assets.car` 存在。
- `Info.plist` 中包含编译后的 App Icon 名称。
- 图标源文件都是 1024×1024 PNG、无 alpha 通道。
- `UISupportedInterfaceOrientations` 对 iPhone 只声明 portrait。
- 目标设备族只包含 iPhone。

Run:

```bash
xcodegen generate
xcodebuild build \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -derivedDataPath .build/DerivedData
bash scripts/acceptance/assert-iphone-app-metadata.sh \
  .build/DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app
```

Expected: FAIL because the asset catalog and icon are absent.

- [ ] **Step 2: Generate the icon with image2**

调用 image2 生成原创图标，提示词固定为：

- 抽象的两张叠放面试闪卡，其中前卡带简化代码括号/光标，轻微向右滑动形成动势。
- 靛蓝到蓝绿色渐变，清晰轮廓，适合 iOS 主屏幕小尺寸识别。
- 无文字、无数字、无心形、无人脸、无探探或 Tinder 商标元素。
- 构图留足系统圆角安全区，不预先裁圆角，不带透明通道。
- 生成 light、dark、tinted 三种 1024×1024 版本；三者轮廓一致。

人工检查生成结果后只选一套，不把候选废图加入项目。

- [ ] **Step 3: Configure the asset catalog**

- 建立 Asset Catalog 和 `AppIcon.appiconset/Contents.json`，用 iOS single-size 1024 universal/light/dark/tinted 槽位指向三个文件。
- 在 `project.yml` 将 `InterviewFlashcard/Resources` 纳入 app target resources，并从 `InterviewFlashcardCore` 的递归 sources 中排除 `Resources`，避免同一 catalog 被两个 target 编译。
- 设置 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。
- 重新生成 Xcode 工程并构建 Debug App。

- [ ] **Step 4: Run verification**

Run:

```bash
xcodegen generate
xcodebuild build \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -derivedDataPath .build/DerivedData
bash scripts/acceptance/assert-iphone-app-metadata.sh \
  .build/DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app
```

Expected: PASS；构建日志没有 “AppIcon has unassigned children” 或缺失图标警告。

- [ ] **Step 5: Verify with Computer Use**

- 回到 iPhone 17 Pro Max 主屏幕，找到新图标并截图。
- 点击图标，确认从主屏幕启动到竖屏直接题卡。
- 保存为 `diagnostics/acceptance/instant-practice-senior-evaluation/01-home-icon.png`。

- [ ] **Step 6: Commit**

```bash
git add InterviewFlashcard/Resources/Assets.xcassets/Contents.json \
  InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json \
  InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
  InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png \
  InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png \
  project.yml \
  scripts/acceptance/assert-iphone-app-metadata.sh
git diff --cached --check
git commit -m "feat: add interview flashcard app icon"
```

### Task 5: 对新导入题目实施资深级满分答案质量门禁

**Files:**
- Create: `InterviewFlashcard/Features/Import/FullScoreAnswerQualityPolicy.swift`
- Create: `InterviewFlashcardTests/FullScoreAnswerQualityPolicyTests.swift`
- Modify: `InterviewFlashcard/Features/Import/ImportCoordinator.swift`
- Modify: `InterviewFlashcard/Core/AI/PromptCatalog.swift`
- Modify: `InterviewFlashcardTests/ImportCoordinatorTests.swift`
- Modify: `InterviewFlashcardTests/Support/Fixtures.swift`

**Interfaces:**
- Consumes: `RefinedCardDraft.fullScoreAnswer`、`ImportCoordinator.stage(...)`/`activate(...)` 和现有 `ReferenceAnswerVersionRecord.keyPointsJSON`。
- Produces: `FullScoreAnswerQualityPolicy.assess(_:)`，返回通过时的 `[String]` 关键点或具体拒绝原因；提示词版本 `refine-senior-v2`；Task 6 将这些关键点作为评分参照。

- [ ] **Step 1: Write the failing tests**

定义并测试 `FullScoreAnswerQualityPolicy.assess(_:)`：

- 少于 120 个去空白后的 grapheme、只有一两句话或只有空泛定义时拒绝。
- 必须包含“结论”“核心要点”“边界与取舍”三个 Markdown 小节。
- “核心要点”至少提取 3 个非重复 bullet；空 bullet、重复措辞不计。
- 合格答案返回可直接编码到 `keyPointsJSON` 的关键点数组。
- `ImportCoordinator.stage` 对整个 50 题批次先完成质量校验；其中一题不合格时整批拒绝，SwiftData 中不得留下部分 staged records。
- `activate` 再次校验，防止绕过 stage；成功后将关键点写入现有 `ReferenceAnswerVersionRecord.keyPointsJSON`。

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/FullScoreAnswerQualityPolicyTests \
  -only-testing:InterviewFlashcardTests/ImportCoordinatorTests
```

Expected: FAIL because the current importer only checks that the answer is nonempty.

- [ ] **Step 3: Write the minimal implementation**

- 新增纯 `FullScoreAnswerQualityPolicy` 和可展示的失败原因。
- 将生成/润色提示词升级为 `refine-senior-v2`，要求输出三个固定小节、至少三个关键点、机制说明、边界/失败模式、工程权衡和追问素材。
- 在 `stage` 的任何 SwiftData mutation 之前校验完整批次。
- 在 `activate` 二次校验并编码关键点；不得新增 schema 字段。
- 更新 fixtures 与验收种子，使所有正向数据满足同一门禁，不在测试中开后门。
- 已存在的历史短答案继续可读；本任务只约束新导入和重新生成的数据，不做自动批量重写。

- [ ] **Step 4: Run tests to verify they pass**

重复 Step 2 命令。

Expected: PASS，并包含“一题失败、整批零写入”的断言。

- [ ] **Step 5: Verify with Computer Use**

- 从独立导入入口导入一份包含短答案的测试 Markdown，确认 UI 显示具体失败原因。
- 导入合格真实题目，确认成功进入题库；练习页题卡正面仍不泄露满分答案。
- 保存为 `diagnostics/acceptance/instant-practice-senior-evaluation/07-import-quality-rejection.png` 和 `08-import-quality-success.png`。

- [ ] **Step 6: Commit**

```bash
git add InterviewFlashcard/Features/Import/FullScoreAnswerQualityPolicy.swift \
  InterviewFlashcard/Features/Import/ImportCoordinator.swift \
  InterviewFlashcard/Core/AI/PromptCatalog.swift \
  InterviewFlashcardTests/FullScoreAnswerQualityPolicyTests.swift \
  InterviewFlashcardTests/ImportCoordinatorTests.swift \
  InterviewFlashcardTests/Support/Fixtures.swift
git diff --cached --check
git commit -m "feat: enforce senior reference answer quality"
```

### Task 6: 收紧 DeepSeek 单次评分并保存题目相关证据

**Files:**
- Create: `InterviewFlashcard/Features/Evaluation/EvaluationDetailPayload.swift`
- Create: `InterviewFlashcardTests/EvaluationDetailPayloadTests.swift`
- Modify: `InterviewFlashcard/Core/AI/AISchemas.swift`
- Modify: `InterviewFlashcard/Core/AI/PromptCatalog.swift`
- Modify: `InterviewFlashcard/Core/AI/DeepSeekAIClient.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerProcessingService.swift`
- Modify: `InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift`
- Modify: `InterviewFlashcardTests/AIResponseValidatorTests.swift`
- Modify: `InterviewFlashcardTests/AnswerProcessingServiceTests.swift`
- Modify: `InterviewFlashcardTests/EvaluationPresentationTests.swift`
- Modify: `InterviewFlashcardTests/Support/Fixtures.swift`

**Interfaces:**
- Consumes: Task 5 保存的参考答案与关键点、`EvaluationRequest` 的原始回答，以及现有 `EvaluationRecord.feedbackJSON`。
- Produces: `EvaluationDetailPayload` v2、`EvaluationRubric.seniorSoftwareEngineer`、提示词版本 `evaluate-senior-v3`，并由 `EvaluationPresentation` 输出六维分数、反馈、证据、遗漏点、gaps、warnings 和 score range，供 Task 7 展示。

- [ ] **Step 1: Write the failing schema and persistence tests**

覆盖以下契约：

- rubric 版本为 `senior-software-engineer-v2`，六维顺序和权重固定。
- 评分提示词版本为 `evaluate-senior-v3`，明确回答可能来自语音/输入法转录：忽略不影响语义的同音字和标点噪声，但缺失知识仍扣分，AI 不得替用户补答案。
- 每个维度必须有非空 `feedback`、至少一条能在原始回答中定位的 `evidence.quote` 及其解释。
- 未得满分的维度必须给出具体 `missedPoints`；总分非 100 时至少有一个 gap 和一个可执行 improvement。
- factual error 必须说明与参考答案或公认机制的冲突依据。
- 响应里的 prompt/rubric 版本若与请求不一致则拒绝；客户端保存请求端的权威版本，不能信任模型自行回填的元数据。
- `EvaluationDetailPayload v2` 往返编码六维详情、gaps、warnings、scoreRange。
- 旧的 `[String:String]` feedback JSON 仍可读取并转成 legacy presentation。
- `AnswerProcessingService` 只调用一次 `evaluate`、零次 `polish`，且 `rawText == polishedText`；完整详情进入现有 `feedbackJSON`。

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AIResponseValidatorTests \
  -only-testing:InterviewFlashcardTests/AnswerProcessingServiceTests \
  -only-testing:InterviewFlashcardTests/EvaluationDetailPayloadTests \
  -only-testing:InterviewFlashcardTests/EvaluationPresentationTests
```

Expected: FAIL because evidence/missed points are currently discarded and validation is too permissive.

- [ ] **Step 3: Write the minimal implementation**

- 新增 `EvaluationDetailPayload`，顶层包含 `schemaVersion = 2`、六维明细、gaps、warnings 和 score range。
- 保持 `EvaluationRecord` 模型不变，把 v2 payload 编码到 `feedbackJSON`。
- `EvaluationPresentation` 先尝试 v2 解码，失败时回退旧 `[String:String]`，不得让历史记录崩溃或空白。
- 新增 `EvaluationRubric.seniorSoftwareEngineer`，沿用 35/25/15/10/10/5 权重并升级版本号。
- 更新 `PromptCatalog`：一个请求同时完成 ASR 容错、六维评分、引用证据、缺失点和改进建议。删除运行路径中对 refine/polish 的调用，不必删除旧协议字段，以保持历史记录兼容。
- `AIResponseValidator` 实施上述结构和语义门禁；校验引用时允许规范化空白和全半角标点，但不得接受模型编造的原文。
- `DeepSeekAIClient` 用请求对象中的 prompt/rubric 版本规范化返回值。
- `AnswerProcessingService` 保持 `rawText` 原样存储，兼容字段 `polishedText` 写同一文本，不新增网络往返。

- [ ] **Step 4: Run tests to verify they pass**

重复 Step 2 命令。

Expected: PASS；spy client 断言 `evaluateCallCount == 1` 且 `polishCallCount == 0`。

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Evaluation/EvaluationDetailPayload.swift \
  InterviewFlashcard/Core/AI/AISchemas.swift \
  InterviewFlashcard/Core/AI/PromptCatalog.swift \
  InterviewFlashcard/Core/AI/DeepSeekAIClient.swift \
  InterviewFlashcard/Features/Practice/AnswerProcessingService.swift \
  InterviewFlashcard/Features/Evaluation/EvaluationPresentation.swift \
  InterviewFlashcardTests/AIResponseValidatorTests.swift \
  InterviewFlashcardTests/AnswerProcessingServiceTests.swift \
  InterviewFlashcardTests/EvaluationDetailPayloadTests.swift \
  InterviewFlashcardTests/EvaluationPresentationTests.swift \
  InterviewFlashcardTests/Support/Fixtures.swift
git diff --cached --check
git commit -m "feat: persist specific senior evaluation evidence"
```

### Task 7: 在评分页首屏加入六维雷达图

**Files:**
- Create: `InterviewFlashcard/Features/Evaluation/RadarChartLayout.swift`
- Create: `InterviewFlashcard/Features/Evaluation/ScoreRadarChart.swift`
- Create: `InterviewFlashcardTests/RadarChartLayoutTests.swift`
- Modify: `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift`
- Modify: `InterviewFlashcardTests/EvaluationPresentationTests.swift`
- Modify: `InterviewFlashcardTests/TestHost/TestHostApp.swift`

**Interfaces:**
- Consumes: Task 6 的 `EvaluationPresentation` 六维有序数据，单维输入为名称、得分和该维满分。
- Produces: `RadarChartLayout.points(scores:maxScores:size:)` 的六轴几何结果和 `ScoreRadarChart`；Task 8 通过 `evaluation.radar` accessibility identifier 验收。

- [ ] **Step 1: Write the failing geometry and presentation tests**

在 `RadarChartLayoutTests` 验证：

- 固定六轴顺序为正确性、覆盖度、推理深度、表达结构、权衡意识、术语精确性。
- 0 分落在中心，满分落在对应外顶点，越界输入被钳制。
- 生成五层同心网格、六条轴线和闭合数据多边形。
- 零尺寸或缺少维度不会产生 NaN/崩溃；缺失维度按 0 展示并附可访问说明。

在 presentation 测试验证结果页顺序：总分 → 雷达图 → 六维具体详情 → 优点/缺口/事实错误/改进 → 原始回答 → 满分答案。历史记录只有在 `polishedText != rawText` 时才显示旧版润色文本。

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/RadarChartLayoutTests \
  -only-testing:InterviewFlashcardTests/EvaluationPresentationTests
```

Expected: FAIL because the result currently uses only linear progress rows.

- [ ] **Step 3: Write the minimal implementation**

- `RadarChartLayout` 只负责归一化与点位计算，便于单元测试。
- `ScoreRadarChart` 使用原生 `Canvas` 或 `Path` 绘制五层网格、六轴和填充多边形，不引入第三方图表依赖。
- 每个维度标签同时显示名称和分数；VoiceOver 将整张图读为六维名称/分数列表。
- `EvaluationResultView` 的首个内容区显示总分和雷达图，线性维度卡移到图下方，并在每维展示模型反馈、原回答证据和缺失点。
- 满分答案完整展示在详细结果区，长文本可选择和滚动；不得退化成一两句摘要。

- [ ] **Step 4: Run tests to verify they pass**

重复 Step 2 命令。

Expected: PASS.

- [ ] **Step 5: Verify with Computer Use**

- 在 Test Host 打开 0 分、混合分、满分三种结果，确认雷达形状与标签正确。
- 使用最大 Dynamic Type 检查标签不遮挡核心数据，详细区可继续纵向滚动。
- 保存为 `diagnostics/acceptance/instant-practice-senior-evaluation/09-evaluation-radar.png` 和 `10-evaluation-details.png`。

- [ ] **Step 6: Commit**

```bash
git add InterviewFlashcard/Features/Evaluation/RadarChartLayout.swift \
  InterviewFlashcard/Features/Evaluation/ScoreRadarChart.swift \
  InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift \
  InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift \
  InterviewFlashcardTests/RadarChartLayoutTests.swift \
  InterviewFlashcardTests/EvaluationPresentationTests.swift \
  InterviewFlashcardTests/TestHost/TestHostApp.swift
git diff --cached --check
git commit -m "feat: add six-dimension evaluation radar"
```

### Task 8: 用真实题目和真实 DeepSeek 完成端到端验收

**Files:**
- Modify: `InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift`
- Modify: `docs/acceptance/computer-use-runbook.md`
- Modify: `scripts/acceptance/run-final-checks.sh`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/01-home-icon.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/02-cold-launch.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/03-filter-sheet.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/04-left-swipe.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/05-right-swipe-answer.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/06-long-question.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/07-import-quality-rejection.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/08-import-quality-success.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/09-evaluation-radar.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/10-evaluation-details.png`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/entry-state.json`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/computer-use-state.json`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/network-counts-redacted.log`
- Create: `diagnostics/acceptance/instant-practice-senior-evaluation/demo-60s.mov`

**Interfaces:**
- Consumes: Tasks 1–7 的最终 App、`assert-iphone-app-metadata.sh [app-path]`、项目专用 DeepSeek 环境变量和固定模拟器 UDID。
- Produces: 完整自动化检查结果、去敏后的 Computer Use 截图/状态/网络计数及一段不超过 60 秒的竖屏演示视频。

- [ ] **Step 1: Prepare deterministic acceptance data without mocking AI**

- `AcceptanceSeeder` 只负责导入至少三道真实技术题及合格的资深级满分答案，不预置假的评分结果。
- 只从项目专用环境变量 `INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY` 读取真实 DeepSeek key；不得在源码、`project.yml`、日志或诊断产物中写出 key。
- 运行前检查真 AI 模式已启用、mock/stub 模式已关闭；缺 key 时明确失败，不静默回退假评分。
- 选择一段带轻微输入法/语音转文字噪声但语义可辨的真实回答用于验收。

- [ ] **Step 2: Run the complete automated suite**

Run:

```bash
xcodegen generate
xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768'
xcodebuild build \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -derivedDataPath .build/DerivedData
bash scripts/acceptance/assert-iphone-app-metadata.sh \
  .build/DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app
bash scripts/acceptance/run-final-checks.sh
git diff --check
```

Expected: all tests and metadata checks PASS；单元测试 spy 确认一次 evaluation、零次 polish，且扫描没有发现 API key。

- [ ] **Step 3: Run the real-device-shaped Computer Use flow**

先从已经执行过 `source ~/.zshrc` 的 shell 真实启动：

```bash
scripts/dev/build-and-launch.sh \
  --ai deepseek \
  --speech unsupported \
  --fixture real-question-demo
```

Expected: launch log 包含 `ai_provider=deepseek` 和 `fixture=real-question-demo`，不包含 key 值；不得使用 `--ai stub`。

在指定 iPhone 17 Pro Max 模拟器上逐项验收：

1. 终止 App，从主屏幕新 App Icon 点击启动。
2. 确认竖屏、全屏、无上下黑边，并直接出现一张彩色真实题卡。
3. 左滑第一题，确认它只跳过、没有回答历史，并出现下一题。
4. 打开过滤入口，确认全部主题默认选中、“包含已练习题”默认关闭，且没有题量和开始按钮。
5. 关闭过滤，右滑当前题进入回答。
6. 输入带轻微转录噪声的真实回答并提交，等待真实 DeepSeek 返回；期间确认 UI 只有一个评分任务。
7. 确认结果首屏是总分和六维雷达图。
8. 向下滚动，确认每维都有针对原回答的引用证据、具体遗漏和可执行改进；确认满分答案包含资深级结构和至少三个关键点。
9. 返回继续练习，确认自动补卡且没有“本组完成”页。
10. 打开回答历史，确认本题保存了原始回答、具体分数、六维详情和满分答案。

保存：

- 主屏幕图标、冷启动直接题卡、过滤面板截图。
- 左滑、右滑和长问题截图。
- 导入质量拒绝/成功截图。
- 雷达图首屏及具体评价截图。
- Computer Use 状态快照。
- 去敏后的网络计数/应用日志，能证明一次评分、零次润色。
- 一段不超过 60 秒的竖屏演示视频。

统一存入 `diagnostics/acceptance/instant-practice-senior-evaluation/`，文件名含步骤序号。

- [ ] **Step 4: Update the runbook and final checklist**

在 `computer-use-runbook.md` 写清：

- 固定设备与 UDID。
- 冷启动直达卡片、纯随机与单题循环预期。
- 过滤默认值和两类空状态。
- 真 DeepSeek 单请求验收与密钥去敏规则。
- 雷达图、具体证据和资深满分答案的检查点。
- 证据目录和失败时的诊断命令。

让 `run-final-checks.sh` 串联工程生成、完整测试、metadata 检查和证据完整性检查，但不要自动提交或发送外部消息。

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift \
  docs/acceptance/computer-use-runbook.md \
  scripts/acceptance/run-final-checks.sh \
  diagnostics/acceptance/instant-practice-senior-evaluation/01-home-icon.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/02-cold-launch.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/03-filter-sheet.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/04-left-swipe.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/05-right-swipe-answer.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/06-long-question.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/07-import-quality-rejection.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/08-import-quality-success.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/09-evaluation-radar.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/10-evaluation-details.png \
  diagnostics/acceptance/instant-practice-senior-evaluation/entry-state.json \
  diagnostics/acceptance/instant-practice-senior-evaluation/computer-use-state.json \
  diagnostics/acceptance/instant-practice-senior-evaluation/network-counts-redacted.log \
  diagnostics/acceptance/instant-practice-senior-evaluation/demo-60s.mov
git diff --cached --check
git commit -m "test: verify instant practice with live evaluation"
```

## Completion Criteria

- 从 iPhone 17 Pro Max 主屏幕点击新图标后，App 始终以竖屏全屏启动并直接展示可滑动题卡。
- 代码和 UI 中不存在练习题量选择、开始练习步骤、有限会话目标和完成页。
- 左滑跳过、右滑回答；题池非空时始终补卡，纯随机且允许已跳过题再次出现。
- 主题和“包含已练习题”只在次级过滤面板中；后者默认关闭。
- 题卡足够大、问题居中、配色稳定且具备可访问对比度，长题和大字体不截断。
- App Icon 已由 image2 生成并通过 Asset Catalog 正确打包。
- 新导入满分答案通过资深级质量门禁，关键点进入现有 JSON 字段。
- 每次回答只调用一次真实 DeepSeek 评分，零次润色；转录噪声在同一提示词中处理。
- 结果页先展示六维雷达图，再展示可追溯到具体题目、原回答和满分答案关键点的评价。
- 旧评分记录仍可打开，且没有 SwiftData schema 迁移。
- 全量测试、metadata 脚本、`git diff --check` 和 Computer Use 验收全部通过，证据齐全且不含密钥。

## Plan Self-Review

- **需求覆盖：** prompt_2 的 App Icon、启动即卡片、无限流、次级过滤、大彩色居中卡片、六维图、具体评价和资深满分答案都有独立任务与验收。
- **与既有决定一致：** 保留纯随机、左跳过/右回答、已练习默认关闭、无云端转写、真实 DeepSeek、零润色和一题一张卡。
- **数据安全：** 评分与关键点复用现有 JSON 字段；不引入 SwiftData schema 迁移；整批导入先校验后写入，避免半批脏数据。
- **兼容性：** 新评分 payload 有版本号并保留旧 `[String:String]` 解码路径；历史 `polishedText` 仅在确实不同于原文时展示。
- **可测试性：** 随机池、卡片主题、答案门禁、评分 payload 和雷达几何均拆成纯逻辑，UI 行为另由 Test Host 与 Computer Use 验收。
- **性能与网络：** 每次提交保持一个 DeepSeek 请求；没有隐藏的润色链路。无限流只维护当前题和最近动作，不积累无限 session 数组。
- **可访问性：** 卡片、滑动动作和雷达图都有非颜色提示、按钮等价操作、VoiceOver 文本与 Dynamic Type 验收。
- **风险控制：** 最容易出错的回答提交 ID 语义、单题池循环、旧 JSON 回退、模型伪造 evidence 和 App Icon metadata 都有明确回归测试。
- **YAGNI：** 本轮不持久化练习过滤、不增加推荐算法、不增加第三方图表库、不批量重写历史满分答案，也不扩展到其他设备。

## 执行状态（2026-08-08）

### 已完成

- Task 1–7 的实现已合入提交：`1dbd3db`、`56a3274`、`254cbaf`、`76ec601`、`1f8a77e`、`5cf0860`、`805ff89`、`ae82b3d`、`c120eba`、`beacee7`、`ceba629`。
- 真实验收种子只写入三道技术题和资深级满分答案，不预置评分结果；DeepSeek provider 通过项目专用环境变量注入，且会在图标冷启动时复用已选 provider，不会静默退回 Stub。
- 指定设备 `iPhone 17 Pro Max / 779ACF98-BD23-4880-9F03-8DB9B9E43768` 的 Computer Use 已验证：主屏幕图标、冷启动直达题卡、过滤面板、左滑跳过、右滑进入回答、长题、禁用本地语音入口、真实文字提交和回答历史。
- 全量测试 `114 tests, 0 failures`、Debug 构建、iPhone-only 竖屏/图标 metadata 和 `git diff --check` 均通过。
- 真实 DeepSeek 结果已持久化：两次独立的 `evaluate-senior-v3` 请求均 HTTP 200、零次 polish；历史记录首条评分 52/100（正确性 65、覆盖度 55、术语精确性 35、推理深度 50、表达结构 30、权衡意识 35），最新结果页评分 59/100（正确性 75、覆盖度 45、术语精确性 60、推理深度 40、表达结构 70、权衡意识 50）。Computer Use AX 同时确认了雷达图、原回答引用、具体遗漏点和改进建议。
- 演示视频已裁剪为严格 60.000 秒；所有证据均未包含 API key。

### 明确阻塞（不以假证据替代）

- `07-import-quality-rejection.png`、`08-import-quality-success.png`：真实模型导入质量分支在当前 Computer Use 会话中无法稳定复现，不能用 Stub 或手工截图冒充。
- `09-evaluation-radar.png`：已补做一次真实 DeepSeek 评分并通过 Computer Use 停留在 `EvaluationResultView`，截图显示 59/100 和六维雷达图；历史详情页仍只展示六维分数行。
- `10-evaluation-details.png` 已保存为真实历史详情截图，显示 52/100 和六维分数；它不是雷达图截图。

### 证据入口

- 自动化：`diagnostics/acceptance/instant-practice-senior-evaluation/tests-real-after-persistence.log`、`build-after-persistence.log`
- 真实状态：`entry-state.json`（首条 15:46 历史记录）、`computer-use-state.json`（含最新雷达结果页）、`network-counts-redacted.log`
- Computer Use 截图：`01-home-icon.png`、`02-cold-launch.png`、`03-filter-sheet.png`、`04-left-swipe.png`、`05-right-swipe-answer.png`、`06-long-question.png`、`10-evaluation-details.png`
- 视频：`demo-60s.mov`（60.000 秒）
