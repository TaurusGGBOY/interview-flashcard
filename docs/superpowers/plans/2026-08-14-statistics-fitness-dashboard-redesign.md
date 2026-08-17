# Statistics Fitness Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将统计页重做为 Apple Fitness 风格的彩色原生 iOS 仪表盘，并用环图、面积趋势图、雷达图、30 天热力图和 Topic 进度条表达不同统计维度。

**Architecture:** 继续使用 `InsightsAggregator.Snapshot` 作为唯一真实数据源；在 `InsightsChartData` 增加 30 天逐日活动数据适配，不改变现有统计口径。`InsightsView` 负责范围选择和页面编排，新的 dashboard 组件负责顶部指标环、热力图与现代化卡片视觉，现有 Swift Charts 和经过测试的 `RadarChartLayout` 继续复用。

**Tech Stack:** Swift 6、SwiftUI、Swift Charts、SwiftData、Core Graphics、XCTest、iOS Human Interface Guidelines。

## Global Constraints

- 保留现有活跃题目、已练习、已评分、Topic 范围和趋势统计口径；不生成假数据。
- 不引入第三方图表库；只使用 Swift Charts、SwiftUI Canvas/Path、系统颜色和 SF Symbols。
- 视觉方向为 Apple Fitness：彩色但克制，使用系统背景、渐变强调色、连续圆角和清晰层级；支持浅色/深色模式与 Dynamic Type。
- 现有 `InsightsAccessibilityID` 和 VoiceOver 文字摘要必须继续可用；图表不能只靠颜色传达含义。
- 保留“全部 Topic/指定 Topic”范围选择与 `@SceneStorage` 持久化行为。
- 先写/更新纯数据测试，再实现视觉组件，最后执行全量测试和模拟器验收。

---

### Task 1: Add heatmap data adapter and dashboard metric helpers

**Files:**
- Modify: `InterviewFlashcard/Features/Insights/InsightsChartData.swift`
- Modify: `InterviewFlashcardTests/InsightsChartDataTests.swift`

**Interfaces:**
- Consumes: `InsightsAggregator.Snapshot.trend`, current date, and the existing calendar.
- Produces: a stable 30-day sequence of date/count records for the activity heatmap; empty snapshots produce an empty sequence.

  - [x] **Step 1: Write the failing data tests**

  Add tests that construct a snapshot with activity on non-consecutive days and assert the new heatmap adapter returns every day in the requested window, preserves counts on active days, inserts zero-count days, sorts ascending by date, and returns an empty result when there are no cards or attempts.

  - [x] **Step 2: Run the focused chart-data tests**

  Run `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max - DeepSeek Live UI,OS=27.0' -only-testing:InterviewFlashcardTests/InsightsChartDataTests CODE_SIGNING_ALLOWED=NO`.

  Expected: the new tests fail because the heatmap record and adapter do not exist yet.

  - [x] **Step 3: Implement the pure adapter**

  Add a `DailyActivityMetric` value type with a stable date identifier, answer count, and a display label. Add an adapter that accepts a snapshot, `asOf`, calendar, and day count, normalizes the snapshot trend by calendar day, and returns a contiguous ascending window ending on `asOf`'s calendar day. Do not alter `InsightsAggregator` or invent scores for zero-activity days.

  - [x] **Step 4: Run the focused chart-data tests again**

  Re-run the command from Step 2 and expect all chart-data tests to pass, including the pre-existing coverage, score, activity, dimension, topic, and trend assertions.

---

### Task 2: Build the Fitness-style visual components

**Files:**
- Create: `InterviewFlashcard/Features/Insights/InsightsDashboardComponents.swift`
- Modify: `InterviewFlashcard/Features/Insights/InsightsCharts.swift`
- Reuse: `InterviewFlashcard/Features/Evaluation/RadarChartLayout.swift`

**Interfaces:**
- Consumes: `InsightsAggregator.Snapshot`, `InsightsChartData.DailyActivityMetric`, and existing chart-data metrics.
- Produces: reusable SwiftUI views for the dashboard hero, activity heatmap, radar chart, and visually consistent card internals.

  - [x] **Step 1: Add the dashboard hero card**

  Create a top card with a restrained blue/purple/orange/green palette, a short scope label, and three ring metrics: coverage percentage, average score percentage, and practice-day consistency capped at the 30-day window. Each ring must have a text label and numeric value, use semantic/system colors where possible, and remain legible in dark mode and larger Dynamic Type settings.

  - [x] **Step 2: Replace the six-dimension bars with a radar presentation**

  Render the existing six average dimension values with the tested `RadarChartLayout` geometry, five grid levels, axes, a filled data polygon, and a compact text legend. Keep the existing `insights.dimensions` accessibility identifier and expose all six dimension/value pairs in its VoiceOver value.

  - [x] **Step 3: Add the 30-day activity heatmap**

  Render the contiguous daily metrics as a compact 5-column/7-column adaptive grid of rounded cells. Use intensity tiers based on answer count, include a legend for “无练习/较少/适中/活跃”, and show the total recent activity as text. The cells must have accessible labels containing date and count, and must not require color alone to interpret the value.

  - [x] **Step 4: Modernize the remaining chart interiors**

  Restyle score/trend charts with gradient area fills, compact point annotations, and consistent axis treatment. Replace the Topic comparison chart's dense duplicate bars with a vertical list of progress rows showing Topic name, coverage progress, average score, and question count while retaining the existing selected-topic emphasis. Keep the existing card IDs and empty-state semantics.

  - [x] **Step 5: Add shared visual tokens**

  Define local dashboard spacing, corner radius, shadow/border, and accent-gradient helpers in the new component file rather than scattering literals across every chart. Ensure all colors have a readable fallback in grayscale and no fixed screen coordinates are used.

---

### Task 3: Recompose the statistics page

**Files:**
- Modify: `InterviewFlashcard/Features/Insights/InsightsView.swift`

**Interfaces:**
- Consumes: the existing full snapshot/current scope snapshot and the new dashboard components.
- Produces: a single scrollable Fitness-style statistics dashboard with unchanged Topic filtering and empty states.

  - [x] **Step 1: Preserve the scope picker contract**

  Keep “全部 Topic” and all active Topic options, the `@SceneStorage("insights.selectedScopeID")` key, automatic fallback when a selected Topic disappears, and the existing filter accessibility identifier.

  - [x] **Step 2: Reorder the content hierarchy**

  Place the scope picker first, then the hero card, then score trend, activity heatmap, radar dimensions, Topic progress list, and the remaining detailed trend/activity card as needed to preserve all current metrics without creating a long wall of identical cards. Keep `ScrollView`/`LazyVStack`, grouped background, safe-area padding, and large navigation title.

  - [x] **Step 3: Preserve accessibility summaries and empty states**

  Keep each existing chart card's accessibility ID and update its summary text to match the new visual. With no cards, show the import/add guidance; with cards but no scores, keep coverage/activity visible and show a clear no-score state for score/radar sections; with no recent activity, show an empty heatmap state instead of a misleading all-zero chart.

  - [x] **Step 4: Build the app**

  Run `DEVELOPER_DIR='/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer' xcodebuild build -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max - DeepSeek Live UI,OS=27.0' -derivedDataPath build/SimulatorUI CODE_SIGNING_ALLOWED=NO`.

  Expected: `BUILD SUCCEEDED` with no SwiftUI/Charts compile errors.

---

### Task 4: Run regression tests and verify the real simulator UI

**Files:**
- Verify: `InterviewFlashcard/Features/Insights/InsightsView.swift`
- Verify: `InterviewFlashcard/Features/Insights/InsightsCharts.swift`
- Verify: `InterviewFlashcard/Features/Insights/InsightsDashboardComponents.swift`
- Verify: `InterviewFlashcard/Features/Insights/InsightsChartData.swift`
- Verify: `InterviewFlashcardTests/InsightsChartDataTests.swift`

**Interfaces:**
- Consumes: the built Debug simulator app and the deterministic `mvp-workflow` acceptance fixture.
- Produces: passing automated checks and visual evidence from the iOS 27 simulator.

  - [x] **Step 1: Run the full XCTest suite**

  Run the project-wide `xcodebuild test` command against the iPhone 17 Pro Max iOS 27 simulator and expect all existing tests plus the new heatmap tests to pass.

  - [x] **Step 2: Install and launch the current build**

  Uninstall only `com.gaoguobin.InterviewFlashcard` from simulator UDID `21887183-46BC-49DC-B907-2BBA04205B66`, install the freshly built app, and launch with the deterministic `mvp-workflow` fixture and stub provider used by the existing acceptance harness.

  - [x] **Step 3: Exercise the statistics page in the simulator**

  Navigate to 统计, verify the hero rings, score area chart, heatmap, radar chart, and Topic progress rows are visible, then switch the scope picker to a real Topic and confirm the scoped values change while the Topic comparison remains populated. Capture a screenshot at the final all-Topic state and one scoped state.

  - [x] **Step 4: Check presentation boundaries**

  Inspect light mode, dark mode, empty/no-score behavior, small-screen scrolling, accessible text summaries, and that no chart is clipped behind the tab bar or navigation bar. Run `git diff --check` and record the build/test/simulator artifact paths in the final response.

---

## Self-review checklist

- [x] Scope is limited to one subsystem: the existing statistics dashboard's data presentation and layout.
- [x] Existing statistical definitions remain in `InsightsAggregator`; only a pure chart-data adapter is extended.
- [x] The design uses multiple visual encodings: rings, area/line, radar, heatmap, and progress rows.
- [x] Every new visual has a textual/accessibility fallback and empty-state behavior.
- [x] The plan contains no production implementation body or copy-pastable feature code.
