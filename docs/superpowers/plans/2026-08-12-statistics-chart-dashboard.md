# Statistics Chart Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将统计页改造成符合 iOS 审美的原生图表仪表盘，并支持按 Topic 查看同一套统计指标，同时保持现有统计口径、真实数据和无数据状态的清晰反馈。
**Architecture:** `InsightsAggregator` 负责按范围聚合真实业务数据；新增纯值类型的 chart-data adapter 将快照转换为图表行；新增可复用 Swift Charts 卡片负责视觉呈现；`InsightsView` 负责查询、Topic 范围选择、页面编排和持久化选择状态。默认 `.all` 范围保持现有调用方兼容。
**Tech Stack:** Swift 6、SwiftUI、Swift Charts、SwiftData、XCTest、iOS Human Interface Guidelines。

## Global Constraints

- 不使用 stub、假题目或假评分；所有图表都只来自 `QuestionCardRecord`、`AnswerAttemptRecord` 和已有评估数据。
- 保留现有统计口径：活跃题目才计入题目统计；被丢弃题目及其回答不计入；回答次数包含未评分回答；平均分、六维平均分和趋势分数只使用 `EvaluationStatus.completed` 且有总分的评估。
- `InsightsAggregator.snapshot(...)` 的现有默认调用方式必须继续编译并保持 `.all` 结果，不能破坏端到端测试和已有数据。
- Topic 筛选只影响当前范围的总览、覆盖率、回答/练习活动、分数、六维平均分和趋势；Topic 对比图仍展示所有活跃 Topic，便于用户比较当前范围与其他 Topic。
- 使用原生 Swift Charts，不引入第三方图表库；使用系统语义色、Dynamic Type、标准 SF Symbols 和系统背景色，支持浅色/深色模式。
- 页面采用原生 `ScrollView`/`LazyVStack` 和卡片分组，触控目标至少 44pt，图表不能只依赖颜色表达信息，每张图表都提供 VoiceOver 的文字摘要。
- 不在页面中保留原先“指标—数值”“Topic—文字”“日期—文字”的统计列表作为主要展示；统计信息统一进入图表卡片，但空状态和辅助说明仍使用文本。
- 先完成本计划文件，再按任务顺序实现；每个任务都要有对应测试或构建验证。

---

## Task 1: Extend the aggregation contract with a Topic scope

**Files:**
- Modify: `InterviewFlashcard/Features/Insights/InsightsAggregator.swift`
- Modify: `InterviewFlashcardTests/InsightsAggregatorTests.swift`
- Verify callers: `InterviewFlashcard/Features/Insights/InsightsView.swift`, `InterviewFlashcardTests/EndToEndWorkflowTests.swift`

- [x] 在 `InsightsAggregator` 中增加可比较的范围类型，至少支持 `.all` 和 `.topic(UUID)`；将范围记录在 `Snapshot` 中，便于页面和无障碍摘要明确当前查看范围。
- [x] 扩展 `snapshot(asOf:calendar:cards:attempts:)` 为带默认值的 `scope` 参数，保留原签名的调用习惯和 `.all` 结果。
- [x] 将卡片和回答先按活跃卡片集合过滤，再按 scope 过滤当前统计输入；选中 Topic 不存在或没有活跃卡片时返回稳定的零值/空趋势快照。
- [x] 保持所有现有口径，特别区分“回答过的题目”与“已评分回答”，并确保 pending/failed/无总分评估不进入分数和维度平均值。
- [x] 让 `topicSummaries` 继续基于全部活跃 Topic 生成，且每个 Topic 的覆盖率和分数只使用自身题目；避免用当前筛选范围错误地污染 Topic 对比数据。
- [x] 在聚合过程中用按题目 ID、Topic ID 和日期的字典/集合复用分组结果，避免 Topic 筛选后对每个 Topic 反复扫描全部回答。
- [x] 添加测试覆盖：两个 Topic 的 `.all` 与各自 `.topic(UUID)` 的题目数、覆盖率、回答数、7/30 日活动、平均分、六维平均分和趋势互相隔离；覆盖被丢弃题目、未评分回答和空 Topic。
- [x] 运行 Insights 聚合单元测试，并确认端到端工作流中原有的默认快照断言仍然通过。

## Task 2: Add a pure chart-data adapter

**Files:**
- Create: `InterviewFlashcard/Features/Insights/InsightsChartData.swift`
- Create: `InterviewFlashcardTests/InsightsChartDataTests.swift`

- [x] 定义不依赖 SwiftUI `Color` 的图表行模型：覆盖率分段、分数指标、活动指标、六维指标、Topic 对比指标和趋势点；每行具备稳定 ID、可读标签、数值和必要的系列类型。
- [x] 将 `InsightsAggregator.Snapshot` 转换为以下图表数据：练习/未练习环图、平均/最近/最佳分柱图、回答活动柱图、六维横向柱图、Topic 覆盖率/平均分对比图、趋势分数折线/面积图与回答次数柱图。
- [x] 保持分数和覆盖率统一为 0–100，计数保留整数语义；无分数、无题目和无趋势时返回空数据而不是造出 0 分的假数据点。
- [x] 提供图表标题、图例和 VoiceOver 摘要所需的纯文本辅助方法，确保图表即便颜色被关闭也能传达“项目—数值”。
- [x] 测试正常快照的分类和值、空快照的空数据行为、未评分回答不进入分数图但进入活动图，以及 Topic 筛选后 adapter 只输出选中范围的主指标。

## Task 3: Build reusable native Swift Charts cards

**Files:**
- Create: `InterviewFlashcard/Features/Insights/InsightsCharts.swift`

- [x] 添加统一的统计卡片容器：使用 `secondarySystemGroupedBackground`、约 20pt 连续圆角、16pt 内边距和系统阴影/边框克制处理，适配深色模式和 Dynamic Type。
- [x] 使用 `SectorMark` 实现覆盖率环图，中心显示百分比和“已练习/总题目”文本；无题目时显示明确的空状态。
- [x] 使用 `BarMark` 实现平均分、最近分、最佳分对比，固定 0–100 语义 Y 轴并以文字标签/图例区分指标；无评分时显示“暂无评分数据”。
- [x] 使用计数柱图展示总回答、已评分、未评分、练习天数、近 7 日和近 30 日活动，避免把不同单位强行叠在同一个比例轴上；必要时拆成同一卡片内的两组图。
- [x] 使用横向 `BarMark` 展示六维平均分，保证长维度名称在 Dynamic Type 下仍可读。
- [x] 使用横向 Topic 对比图展示所有活跃 Topic 的覆盖率和平均分，并在卡片说明中标识当前选中的 Topic；没有 Topic 时显示空状态。
- [x] 使用 `AreaMark`/`LineMark` 展示平均分趋势，并用独立的 `BarMark` 展示每日回答次数，避免分数和次数共享误导性尺度；日期为空时显示空状态。
- [x] 为每个图表设置合理高度、轴标签、图例、可读颜色映射和必要的数据点标注；不使用绝对屏幕坐标，允许横向滚动或系统压缩以适配小屏和大字体。
- [x] 为每个卡片提供稳定的 `accessibilityIdentifier` 与 `.accessibilityElement(children: .ignore)` 摘要，摘要包含当前范围、关键数值和“暂无数据”状态，不仅依赖图形或颜色。

## Task 4: Replace the statistics list with the chart dashboard and Topic picker

**Files:**
- Modify: `InterviewFlashcard/Features/Insights/InsightsView.swift`

- [x] 将现有 `List` 改为带大标题的 `ScrollView` + `LazyVStack`，采用系统 grouped background、20pt 左右边距、16pt 卡片间距和安全区内布局。
- [x] 在顶部增加原生 `Picker`（`.menu` 样式），提供“全部 Topic”和所有活跃 Topic；使用 `@SceneStorage` 保存选择，选择的 Topic 被删除或丢弃后自动回退到“全部 Topic”。
- [x] 基于同一份真实 SwiftData 查询生成全量快照和当前 scope 快照，将当前 scope 快照交给总览图表，将全量 Topic summaries 交给 Topic 对比图。
- [x] 按顺序编排筛选头部、覆盖率、分数、活动、六维、Topic 对比、趋势图表卡片；保留屏幕和现有统计入口的导航标题，更新/保留自动化需要的语义 ID。
- [x] 设计分层空状态：完全没有题目时提示导入或添加题目；有题目但没有评分时仍展示覆盖率和活动图，并在分数相关卡片提示暂无评分；没有 Topic 时给出明确文本状态。
- [x] 确认 SwiftData `@Query` 数据变化后图表会自动刷新，切换 Topic 不会创建或修改任何题目、回答或评估数据。
- [x] 检查 VoiceOver 标签、Dynamic Type、浅色/深色模式、横屏/小屏布局和最小触控区域；不引入 stub 数据或仅为 UI 生成的测试记录。

## Task 5: Run automated checks and verify the simulator UI

**Files:**
- Verify: `InterviewFlashcard/Features/Insights/InsightsAggregator.swift`
- Verify: `InterviewFlashcard/Features/Insights/InsightsChartData.swift`
- Verify: `InterviewFlashcard/Features/Insights/InsightsCharts.swift`
- Verify: `InterviewFlashcard/Features/Insights/InsightsView.swift`
- Verify: `InterviewFlashcardTests/InsightsAggregatorTests.swift`
- Verify: `InterviewFlashcardTests/InsightsChartDataTests.swift`

- [x] 运行 `xcodegen generate`，确保新增 Swift 文件被项目自动包含且没有生成文件漂移。
- [x] 使用项目配置的 Xcode beta 和 iOS Simulator 执行 `InterviewFlashcardTests` 全量测试；至少单独复跑 Insights 聚合、chart-data 和端到端工作流测试。
- [x] 用现有真实模拟器数据构建并启动应用，进入“统计”页，确认默认“全部 Topic”能显示图表，再切换至少一个真实 Topic，确认所有主指标与范围变化一致。
- [x] 截图检查浅色/深色模式下的卡片、坐标轴、图例、空状态和大字体布局；确认图表没有被导航栏、底部 Tab 或安全区遮挡。
- [x] 若构建或 UI 验证失败，定位到真实根因并修复后重新运行对应检查，不用 stub 绕过失败。
- [x] 最终报告修改文件、测试命令/结果、模拟器验证结果，以及按照 iOS HIG 对可访问性、Dynamic Type、颜色和触控区域的自评改进项。

---

## Self-review checklist

- [x] 需求覆盖：全部统计改为图表、支持 Topic 筛选、原生 iOS 视觉、先写计划后执行、自动化和模拟器验证。
- [x] 数据一致性：默认 scope 兼容现有调用方；活跃/丢弃、未评分/已评分和 Topic 隔离口径均有明确实现与测试。
- [x] 文件可定位：每个任务给出精确文件、接口边界、测试位置和验收步骤。
- [x] 无占位内容：没有 TBD、TODO、伪代码或“类似地实现”的模糊步骤。
- [x] 可执行性：任务按聚合契约 → 纯数据 → 图表组件 → 页面接入 → 验证的顺序排列，任一步都有可运行的检查。
