# Interview Flashcard MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本机从零构建并运行一个面向个人 iPhone 的 Interview Flashcard MVP，完成 Markdown AI 建库、随机练习、文字/本地语音回答、AI 润色与六维评分、历史、统计、回收站和本地持久化，并让每个功能都通过 macOS Computer Use 驱动的真实 Simulator 验收。

**Architecture:** 使用单一 SwiftUI iOS App，按 Library、Import、Practice、History、Insights、Settings 能力边界组织代码；SwiftData 保存结构化数据，Application Support 保存 M4A，Keychain 保存 DeepSeek API Key。所有外部 AI 和语音能力均通过协议注入，单元测试与 UI 验收使用确定性实现，正式运行使用 DeepSeek 和 Apple Speech；DEBUG 构建提供只读诊断快照，供 UI 之外验证持久化状态。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、Swift Charts、AVFoundation、Speech、Security/Keychain、swift-markdown、XcodeGen、XCTest、iOS 26+ Simulator、DeepSeek Chat Completions API、Codex Computer Use。

## Global Constraints

- 产品只面向个人 iPhone；MVP 不实现账号、应用后端、同步、Android、Web 或 App Store 发布流程。
- MVP 不实现 FSRS、遗忘曲线、自动复习队列、连续打卡奖励、排行榜、社区题库或游戏化；复习只通过 Topic 筛选和“包含已练习题”完成。
- 部署目标固定为 iOS 26.0，Swift language mode 固定为 Swift 6；依赖只通过 Swift Package Manager 引入。
- 一张 Question Card 恰好属于一个 Topic；AI 不能创建 Topic，未知分类必须落入系统内置且不可删除的 Others。
- Markdown 由 AI 自由拆题；本地 AST 只负责结构感知分片、重叠上下文和来源锚点，不把标题直接判定为题目。
- 候选题按同一 SourceDocument 的原始顺序组成 Refinement Batch，每批最多 50 题，不混合源文档；只做批内润色和去重，跨批与重复导入不去重。
- 同一 Markdown 每次导入都创建独立 SourceDocument；导入失败不得激活部分 Question Card，临时 AI 失败自动重试一次，并可继续同一次导入。
- 随机抽题是 Draw Pool 内逐题等概率抽取，一次只显示一张；“包含已练习题”默认关闭，查看或跳过不算练习。
- Answer Attempt 必须先保存原文再调用 AI；Answer Polish 与 Evaluation 是两个请求，润色新增且原文没有的事实不得得分。
- 六维评分固定为正确性 35、覆盖度 25、推理与原理 15、结构与清晰度 10、示例与取舍 10、准确简洁 5；客户端计算 0–100 总分。
- 语音只有在运行时确认设备端转写可用时才能启用；音频永不上传，不允许只有录音而没有文字的提交。
- 删除 Question Card 必须确认并软删除到 Trash；恢复连同历史恢复，永久删除必须二次确认并级联清理 Answer、Evaluation 和音频。
- API Key 只存 Keychain；DeepSeek 请求不得包含音频，日志和 diagnostics 不得记录 API Key。
- 每个功能完成前必须从当前 checkout 本机 build、启动 iOS Simulator、用 Computer Use 真实点击/输入/滚动、按 `Cmd+Shift+3` 保存操作前后全屏截图，并从 UI 外独立读回状态。
- 每个功能证据固定保存到 `diagnostics/mac-ui/<feature-slug>/`，至少包含 `context.txt`、`tests.log`、`build.log`、`launch.log`、`steps.md`、`before.png`、`after.png` 和 `state.json`。
- 自动验收使用确定性本地 AI stub；真实 DeepSeek 只做单独 smoke test，在 UI 输入或保存 API Key 前必须取得用户当次明确确认。
- Simulator 必须验收语音按钮门控、权限失败、录音 UI、转写确认 UI 和提交链路；设备端真实离线转写另需物理 iPhone 证据，两类证据都完成后语音功能才能最终签收。

---

## Execution Gates

本计划按 Task 0 → Task 14 顺序执行。任何任务只有同时满足“聚焦测试通过、全量测试未回归、本机 build 成功、Computer Use 用户路径完成、截图存在、状态读回一致、精确文件已提交”才可勾选完成。

当前机器预检事实：`xcodebuild -version` 指向 `/Library/Developer/CommandLineTools` 并失败，`xcrun simctl` 不存在，`/Applications` 和用户 Applications 目录中没有 Xcode。Task 0 是硬门槛；在完整 Xcode 与 iOS 26 Simulator runtime 可用之前，不得声称 App 已 build、运行或通过 UI 验收。Xcode 安装及许可接受如果需要 Apple ID、管理员授权或服务条款确认，由用户完成；其余步骤由实现者继续执行。

## File Map

### Project and app shell

- Create `project.yml`: XcodeGen 工程定义、iOS 26.0、Swift 6、swift-markdown 依赖、App 与测试 target。
- Create `Config/Debug.xcconfig`: DEBUG 诊断开关与空的默认 AI provider 配置，不含秘密。
- Create `Config/Release.xcconfig`: Release 编译设置，不含 API Key。
- Create `.gitignore`: 忽略 `.build/`、`.local/`、生成的 Xcode 用户状态和 `diagnostics/mac-ui/` 运行证据。
- Create `InterviewFlashcard/App/InterviewFlashcardApp.swift`: App 入口与 ModelContainer 注入。
- Create `InterviewFlashcard/App/AppEnvironment.swift`: AI、语音、音频、时钟、随机源和诊断依赖组装。
- Create `InterviewFlashcard/App/RootTabView.swift`: 练习、题库、历史、统计、设置五个一级入口。
- Create `InterviewFlashcard/Shared/AppRoute.swift`: 稳定导航路由。
- Create `InterviewFlashcard/Shared/AccessibilityID.swift`: Computer Use 使用的稳定可访问性标识。

### Persistence and domain

- Create `InterviewFlashcard/Core/Domain/DomainEnums.swift`: 所有持久化枚举的稳定字符串值。
- Create `InterviewFlashcard/Core/Domain/ScoringRubric.swift`: 六维 key、权重与总分计算。
- Create `InterviewFlashcard/Core/Persistence/Models/TopicRecord.swift`: Topic/Others。
- Create `InterviewFlashcard/Core/Persistence/Models/SourceDocumentRecord.swift`: 一次 Markdown 导入来源。
- Create `InterviewFlashcard/Core/Persistence/Models/ImportRecord.swift`: ImportRun、ImportChunk、QuestionCandidate、RefinementBatch。
- Create `InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift`: QuestionCard 与 ReferenceAnswerVersion。
- Create `InterviewFlashcard/Core/Persistence/Models/AnswerRecord.swift`: AnswerAttempt、PolishResult、Evaluation、AudioAsset。
- Create `InterviewFlashcard/Core/Persistence/Models/ReclassificationRecord.swift`: 手动重新分类任务及批次状态。
- Create `InterviewFlashcard/Core/Persistence/AppSchema.swift`: SwiftData schema 与迁移版本入口。
- Create `InterviewFlashcard/Core/Persistence/AppModelContainer.swift`: 磁盘/内存容器工厂和 Others bootstrap。
- Create `InterviewFlashcard/Core/Persistence/DiagnosticStateExporter.swift`: Task 1 先写最小 App-shell JSON，Task 2 扩展为从 ModelContext 重新 fetch 的状态快照。
- Create `InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift`: DEBUG-only、按稳定名称生成确定性 UI 验收数据，Release 中不可用。

### AI and secure settings

- Create `InterviewFlashcard/Core/AI/AIClient.swift`: 五类 AI 操作的协议边界。
- Create `InterviewFlashcard/Core/AI/AISchemas.swift`: 请求/响应 Codable DTO。
- Create `InterviewFlashcard/Core/AI/AIResponseValidator.swift`: JSON、维度、来源锚点和 topic 白名单校验。
- Create `InterviewFlashcard/Core/AI/RetryingAIClient.swift`: 只对临时错误自动重试一次。
- Create `InterviewFlashcard/Core/AI/DeepSeekAIClient.swift`: URLSession Chat Completions 适配器。
- Create `InterviewFlashcard/Core/AI/StubAIClient.swift`: 确定性验收响应和可注入失败模式。
- Create `InterviewFlashcard/Core/AI/PromptCatalog.swift`: decompose/refine/reclassify/polish/evaluate 的版本化 system prompt。
- Create `InterviewFlashcard/Core/Security/APIKeyStore.swift`: Keychain 协议与实现。
- Create `InterviewFlashcard/Features/Settings/SettingsView.swift`: 模型、API Key、隐私与清除操作。

### Markdown import and library

- Create `InterviewFlashcard/Features/Library/LibraryView.swift`: Topic 列表、Others 固定入口、导入和回收站入口。
- Create `InterviewFlashcard/Features/Library/TopicService.swift`: Topic 创建/重命名/删除规则。
- Create `InterviewFlashcard/Features/Library/TopicEditorView.swift`: Topic 管理 UI。
- Create `InterviewFlashcard/Features/Library/QuestionDetailView.swift`: 题干、来源、满分答案和单题历史入口。
- Create `InterviewFlashcard/Features/Import/MarkdownChunker.swift`: AST 结构单元、拥有区和重叠上下文分片。
- Create `InterviewFlashcard/Features/Import/ImportCoordinator.swift`: 可恢复导入状态机与事务激活。
- Create `InterviewFlashcard/Features/Import/ImportView.swift`: Files 选择、文档级进度、继续处理和结果。
- Create `InterviewFlashcard/Features/Reclassification/ReclassificationService.swift`: 全量 Others、每批 50、失败跳过。
- Create `InterviewFlashcard/Features/Reclassification/OthersView.swift`: 独立入口与简单完成反馈。

### Practice, speech and answer processing

- Create `InterviewFlashcard/Features/Practice/QuestionDrawService.swift`: 纯随机 Draw Pool。
- Create `InterviewFlashcard/Features/Practice/PracticeView.swift`: Topic 多选、筛选、单卡、跳过、下一题。
- Create `InterviewFlashcard/Features/Practice/AnswerSubmissionService.swift`: 原文先落盘与异步处理触发。
- Create `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`: 文字输入、语音入口和提交。
- Create `InterviewFlashcard/Core/Speech/SpeechTranscribing.swift`: 本地转写能力协议。
- Create `InterviewFlashcard/Core/Speech/AppleSpeechTranscriber.swift`: `requiresOnDeviceRecognition = true` 的 Apple Speech 实现。
- Create `InterviewFlashcard/Core/Speech/AudioRecording.swift`: AVAudioRecorder M4A 文件生命周期。
- Create `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`: 录音、转写确认和权限失败 UI。
- Create `InterviewFlashcard/Features/Evaluation/AnswerProcessingService.swift`: polish 后 evaluate、重处理追加版本。
- Create `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`: 原文、润色文、六维分数、反馈与满分答案。

### History, insights and trash

- Create `InterviewFlashcard/Features/History/HistoryView.swift`: 全局倒序历史与筛选。
- Create `InterviewFlashcard/Features/History/AttemptDetailView.swift`: 版本快照、处理版本、录音回放和重新处理。
- Create `InterviewFlashcard/Features/History/QuestionHistoryView.swift`: 单题时间线。
- Create `InterviewFlashcard/Features/Insights/InsightsAggregator.swift`: 覆盖率、次数、天数、分数、维度和 Topic 聚合。
- Create `InterviewFlashcard/Features/Insights/InsightsView.swift`: Swift Charts 与快捷入口。
- Create `InterviewFlashcard/Features/Trash/TrashService.swift`: 软删除、恢复和永久删除级联。
- Create `InterviewFlashcard/Features/Trash/TrashView.swift`: 回收站 UI 与两级确认。

### Tests, fixtures and local acceptance tooling

- Create `InterviewFlashcardTests/Support/TestModelContainer.swift`: 隔离的内存 SwiftData 容器。
- Create `InterviewFlashcardTests/Support/Fixtures.swift`: 稳定 UUID、时钟和样本实体。
- Create `InterviewFlashcardTests/*Tests.swift`: 与上述生产单元一一对应的聚焦测试。
- Create `Tests/Fixtures/sample-interview.md`: 可生成 3 张卡、含 fenced code 假标题和跨块内容的导入样本。
- Create `Tests/Fixtures/long-interview.md`: 强制形成至少 3 个重叠 Import Chunk 和超过 50 个候选的长样本。
- Create `scripts/dev/preflight.sh`: 验证完整 Xcode、iOS 26 runtime、XcodeGen 和 Simulator，输出 `.local/acceptance.env`。
- Create `scripts/dev/test.sh`: 固定 DerivedData 和 destination 的测试入口。
- Create `scripts/dev/build-and-launch.sh`: 从当前 checkout 生成工程、build、安装并启动当前 App。
- Create `scripts/acceptance/start-run.sh`: 初始化功能证据目录并记录 branch/commit/worktree/device/runtime。
- Create `scripts/acceptance/install-fixture.sh`: 把 Markdown fixture 放入 Simulator App Documents。
- Create `scripts/acceptance/collect-screenshot.sh`: 收集 Computer Use 触发的最新 macOS 全屏截图。
- Create `scripts/acceptance/read-state.sh`: 从 App container 读取诊断 JSON。
- Create `scripts/acceptance/finish-run.sh`: 校验每类证据存在且 commit 与当前 checkout 一致。
- Create `docs/acceptance/computer-use-runbook.md`: node_repl 启动、fresh state、操作、截图和失败判定规范。
- Create `docs/acceptance/iphone-offline-speech.md`: 物理 iPhone 断网本地转写检查表。

## Stable Interfaces

以下签名在首次引入后保持稳定，后续任务只能扩展实现，不能私自重命名：

```swift
protocol AIClient: Sendable {
    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse
    func refine(_ request: RefineRequest) async throws -> RefineResponse
    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse
    func polish(_ request: PolishRequest) async throws -> PolishResponse
    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse
}

protocol SpeechTranscribing: Sendable {
    func localCapability(locale: Locale) async -> LocalSpeechCapability
    func transcribe(fileURL: URL, locale: Locale) async throws -> SpeechTranscript
}

protocol AudioRecording: Sendable {
    func start() async throws -> URL
    func stop() async throws -> RecordedAudio
    func cancel() async
}

protocol APIKeyStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}
```

`AIClient` DTO 全部是 `Sendable & Codable & Equatable`。`QuestionDrawService` 接收注入的 `RandomNumberGenerator`，生产环境用 `SystemRandomNumberGenerator`，测试使用固定序列。所有 service 在写 SwiftData 后调用 `DiagnosticStateExporter.export(from:)`；Release 构建中的 exporter 是空操作。

## Computer Use Acceptance Contract

每个业务任务末尾重复执行同一合同，不用 XCTest UI 自动化替代：

1. `scripts/acceptance/start-run.sh <feature-slug>` 记录当前 commit、`git status --short`、Simulator UDID、runtime 和 App bundle ID。
2. `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/<SuiteName>` 保存到 `tests.log`。
3. `scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported` 保存 build/launch log；脚本必须卸载旧 App 后安装当前产物，避免旧构建污染。
4. 通过 `mcp__node_repl__js` 初始化 Computer Use。Xcode 27 使用 Device Hub 承载 Simulator 窗口，验收目标固定为 iPhone 17 Pro Max（UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`）：

```javascript
if (!globalThis.sky) {
  const { setupComputerUseRuntime } = await import("/Users/gaoguobin/.codex/plugins/cache/openai-bundled/computer-use/1.0.1000550/scripts/computer-use-client.mjs");
  await setupComputerUseRuntime({ globals: globalThis });
}
var simulatorState = await sky.get_app_state({ app: "com.apple.dt.Devices" });
nodeRepl.write(simulatorState.text);
```

5. 每次点击或输入前重新调用 `sky.get_app_state({ app: "com.apple.dt.Devices" })`，确认左侧选中 iPhone 17 Pro Max，基于当次可见 label/accessibility identifier 选择元素；不得复用动态 index。操作用 `sky.click`、`sky.type_text`、`sky.press_key` 或 `sky.scroll`，不使用 shell/AppleScript 替代 UI。
6. 操作前后分别执行 `sky.press_key({ app: "Simulator", key: "super+shift+3" })`，再运行 `scripts/acceptance/collect-screenshot.sh <feature-slug> before|after`。
7. `scripts/acceptance/read-state.sh <feature-slug>` 从 `xcrun simctl get_app_container "$IF_SIMULATOR_UDID" com.gaoguobin.InterviewFlashcard data` 下读取 `Library/Application Support/Diagnostics/state.json`；把 UI 结果与 JSON 中实体 ID、数量、状态和分数逐项核对。
8. 把实际操作、可见结果、状态核对和异常写入 `steps.md`，执行 `scripts/acceptance/finish-run.sh <feature-slug>`。任一证据缺失或状态不一致即失败，修复后必须重新跑完整合同。

### Task 0: Unblock and Pin the Local Apple Toolchain

**Files:**
- Create: `scripts/dev/preflight.sh`
- Create: `.gitignore`
- Create: `docs/acceptance/computer-use-runbook.md`
- Create: `docs/acceptance/iphone-offline-speech.md`

**Interfaces:**
- Consumes: Full Xcode installed by the user at `/Applications/Xcode.app` when Apple authorization is required.
- Produces: `.local/acceptance.env` containing `INTERVIEW_XCODE_DEVELOPER_DIR`, `IF_SIMULATOR_UDID`, `IF_SIMULATOR_NAME`, `IF_SIMULATOR_RUNTIME`, and `IF_BUNDLE_ID`.

- [ ] **Step 1: Write the preflight shell test before the script exists**

Run:

```bash
test -x scripts/dev/preflight.sh
```

Expected: exit 1 because the script does not exist.

- [ ] **Step 2: Implement an exact, non-mutating preflight**

`scripts/dev/preflight.sh` must use `set -euo pipefail`, reject `/Library/Developer/CommandLineTools`, require `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`, print `xcodebuild -version`, require an available iOS 26.x runtime and at least one available iPhone Simulator, require `xcodegen`, boot the selected device if needed, wait with `simctl bootstatus -b`, and atomically write `.local/acceptance.env`. It must never call `sudo`, accept a license, install Xcode, or download a runtime.

Use a task-specific environment variable for every command:

```bash
INTERVIEW_XCODE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcodebuild -version
DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl list devices available
```

- [ ] **Step 3: Run preflight and honor the hard gate**

Run: `scripts/dev/preflight.sh`

Expected now: `BLOCKED: full Xcode not found at /Applications/Xcode.app` and non-zero exit. After the user installs full Xcode, accepts its license, installs an iOS 26 Simulator runtime, and `brew install xcodegen` has completed, rerun and expect `READY`, plus a populated `.local/acceptance.env`. Do not continue to Task 1 while the command is non-zero.

- [ ] **Step 4: Write the Computer Use and physical-device runbooks**

The Computer Use runbook must contain the eight-step contract above, the exact node_repl bootstrap, fresh-state rule, `Cmd+Shift+3` rule, evidence filenames, and failure conditions. The physical iPhone runbook must require airplane mode plus Wi-Fi off, supported locale downloaded, real microphone recording, visible transcript, editable confirmation text, submitted attempt, local M4A, and a statement that no network request occurred during transcription.

- [ ] **Step 5: Commit the gate and runbooks**

```bash
git add .gitignore scripts/dev/preflight.sh docs/acceptance/computer-use-runbook.md docs/acceptance/iphone-offline-speech.md
git commit -m "chore: add local Apple toolchain gate"
```

### Task 1: Scaffold a Buildable Five-Tab App and Acceptance Harness

**Files:**
- Create: `project.yml`
- Create: `Config/Debug.xcconfig`
- Create: `Config/Release.xcconfig`
- Create: `InterviewFlashcard/App/InterviewFlashcardApp.swift`
- Create: `InterviewFlashcard/App/AppEnvironment.swift`
- Create: `InterviewFlashcard/App/RootTabView.swift`
- Create: `InterviewFlashcard/Shared/AppRoute.swift`
- Create: `InterviewFlashcard/Shared/AccessibilityID.swift`
- Create: `InterviewFlashcard/Core/Persistence/DiagnosticStateExporter.swift`
- Create: `InterviewFlashcardTests/AppShellTests.swift`
- Create: `scripts/dev/test.sh`
- Create: `scripts/dev/build-and-launch.sh`
- Create: `scripts/acceptance/start-run.sh`
- Create: `scripts/acceptance/collect-screenshot.sh`
- Create: `scripts/acceptance/read-state.sh`
- Create: `scripts/acceptance/finish-run.sh`

**Interfaces:**
- Consumes: `.local/acceptance.env` from Task 0.
- Produces: `AppEnvironment`, `RootTabView`, bundle ID `com.gaoguobin.InterviewFlashcard`, bootstrap `DiagnosticStateExporter`, reusable build/launch and acceptance scripts.

- [ ] **Step 1: Write a failing app-shell test**

```swift
import XCTest
@testable import InterviewFlashcard

final class AppShellTests: XCTestCase {
    func testRootTabsHaveStableChineseTitles() {
        XCTAssertEqual(AppRoute.rootTabs.map(\.title), ["练习", "题库", "历史", "统计", "设置"])
        XCTAssertEqual(Set(AppRoute.rootTabs.map(\.accessibilityID)).count, 5)
    }
}
```

- [ ] **Step 2: Generate the project and prove the test fails**

Run:

```bash
source .local/acceptance.env
DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcodegen generate
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AppShellTests
```

Expected: compile failure because `AppRoute.rootTabs` does not exist.

- [ ] **Step 3: Implement the minimal app shell and project definition**

`project.yml` must define the app and test targets, iOS 26.0, Swift 6, Debug/Release xcconfig, the swift-markdown package from version `0.6.0`, microphone and speech usage descriptions, file sharing, and `LSSupportsOpeningDocumentsInPlace`. `AppRoute.rootTabs` must return exactly five cases with Chinese labels and SF Symbols. Each tab root must render a navigation title and a stable accessibility identifier from `AccessibilityID`.

- [ ] **Step 4: Implement deterministic build/launch scripts**

`scripts/dev/test.sh` and `build-and-launch.sh` must source `.local/acceptance.env`, pass `DEVELOPER_DIR`, use `.build/DerivedData`, destination `platform=iOS Simulator,id=$IF_SIMULATOR_UDID`, and tee logs to a caller-selected path. Build-and-launch must terminate and, unless `--keep-data` is passed, uninstall the bundle; then install `.build/DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app` and launch with `-IFDiagnosticsEnabled YES`, `-IFAIProvider stub|deepseek`, `-IFStubMode <mode>`, `-IFSpeechCapability <value>`, optional `-IFSeedFixture <name>`, and optional `-IFRandomSeed <integer>`. CLI flags are `--ai`, `--stub-mode`, `--speech`, `--fixture`, `--random-seed` and `--keep-data`; unknown options fail with usage text.

- [ ] **Step 5: Make the test and full build pass**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AppShellTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported
```

Expected: one passing test, `** BUILD SUCCEEDED **`, and a launched App process ID.

- [ ] **Step 6: Perform the first Computer Use smoke acceptance**

Use feature slug `app-shell`. Capture `before.png`, click all five tabs using fresh app state each time, verify each navigation title, capture `after.png`, and record the visible labels in `steps.md`. The bootstrap exporter writes exactly `{ "schemaVersion": 1, "topics": [], "cards": [], "attempts": [] }` to the diagnostics location so `read-state.sh` can independently prove the current App launched; Task 2 replaces the empty arrays with SwiftData fetches.

- [ ] **Step 7: Commit the buildable shell**

```bash
git add project.yml Config InterviewFlashcard/App InterviewFlashcard/Shared InterviewFlashcard/Core/Persistence/DiagnosticStateExporter.swift InterviewFlashcardTests/AppShellTests.swift scripts/dev scripts/acceptance
git commit -m "feat: scaffold interview flashcard app"
```

### Task 2: Add the SwiftData Model, Others Bootstrap, and Diagnostic Readback

**Files:**
- Create: `InterviewFlashcard/Core/Domain/DomainEnums.swift`
- Create: `InterviewFlashcard/Core/Domain/ScoringRubric.swift`
- Create: `InterviewFlashcard/Core/Persistence/Models/TopicRecord.swift`
- Create: `InterviewFlashcard/Core/Persistence/Models/SourceDocumentRecord.swift`
- Create: `InterviewFlashcard/Core/Persistence/Models/ImportRecord.swift`
- Create: `InterviewFlashcard/Core/Persistence/Models/QuestionRecord.swift`
- Create: `InterviewFlashcard/Core/Persistence/Models/AnswerRecord.swift`
- Create: `InterviewFlashcard/Core/Persistence/Models/ReclassificationRecord.swift`
- Create: `InterviewFlashcard/Core/Persistence/AppSchema.swift`
- Create: `InterviewFlashcard/Core/Persistence/AppModelContainer.swift`
- Modify: `InterviewFlashcard/Core/Persistence/DiagnosticStateExporter.swift`
- Create: `InterviewFlashcard/Core/Persistence/AcceptanceSeeder.swift`
- Create: `InterviewFlashcardTests/Support/TestModelContainer.swift`
- Create: `InterviewFlashcardTests/Support/Fixtures.swift`
- Create: `InterviewFlashcardTests/PersistenceTests.swift`
- Modify: `InterviewFlashcard/App/InterviewFlashcardApp.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: app shell from Task 1.
- Produces: `AppSchemaV1.models`, `AppModelContainer.make(inMemory:)`, `AppModelContainer.bootstrapOthers(context:)`, `DiagnosticStateExporter.export(from:)`, `AcceptanceSeeder.seed(named:context:)`, async XCTest assertion helpers, and all persisted record types.

- [ ] **Step 1: Write failing persistence invariants**

```swift
@MainActor
func testBootstrapCreatesExactlyOneImmutableOthers() throws {
    let context = try TestModelContainer.make().mainContext
    try AppModelContainer.bootstrapOthers(context: context)
    try AppModelContainer.bootstrapOthers(context: context)
    let topics = try context.fetch(FetchDescriptor<TopicRecord>())
    XCTAssertEqual(topics.count, 1)
    XCTAssertEqual(topics.first?.systemKind, .others)
}

func testRubricComputesWeightedTotalLocally() {
    let scores = DimensionScores(correctness: 80, coverage: 60, reasoning: 80, structure: 80, tradeoffs: 70, precision: 100)
    XCTAssertEqual(ScoringRubric.general.total(for: scores), 75)
}
```

- [ ] **Step 2: Run and observe missing model failures**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/PersistenceTests`

Expected: compile failure for `TopicRecord`, `DimensionScores`, and `ScoringRubric`.

- [ ] **Step 3: Implement stable enum values and record relationships**

Use String-backed persisted values for import status, batch status, input mode, processing status, system topic kind, and score dimension. `QuestionCardRecord` owns `referenceAnswers` and `attempts`, has `trashedAt: Date?`, and points to one Topic and one SourceDocument. `AnswerAttemptRecord` stores immutable `questionTextSnapshot`, `referenceAnswerTextSnapshot`, `referenceAnswerVersion`, `rawText`, `inputMode`, and `submittedAt`; polish/evaluation retries append child records. Deletion relationships must preserve children during soft delete and cascade only when the parent is physically deleted.

- [ ] **Step 4: Implement model container and diagnostic export**

Bootstrap Others idempotently on app launch. When launch argument `-IFDiagnosticsEnabled YES` is present, exporter must fetch active/trashed cards, topics, import runs, attempts, polish results, evaluations, audio assets and reclassification runs, encode sorted deterministic JSON, and atomically replace `Library/Application Support/Diagnostics/state.json`. No raw API key or Authorization header may be represented in its DTO.

`AcceptanceSeeder` compiles only in DEBUG and accepts these exact names: `empty`, `reclassification-103`, `practice-mixed`, `processing`, `history`, `insights`, `trash`, and `mvp-workflow`. It first verifies the store is empty except for Others, then inserts stable UUID/date/text fixtures; it refuses to seed a non-empty store. `Fixtures.swift` also defines `XCTAssertThrowsErrorAsync`, fixed Shanghai calendar/clock, fixed random generator and test fixture builders used in later tasks. Release AppEnvironment ignores every `-IFSeedFixture` and stub-provider argument.

- [ ] **Step 5: Run focused and full tests**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/PersistenceTests
scripts/dev/test.sh
```

Expected: all tests pass and the weighted score assertion equals 75.

- [ ] **Step 6: Build, launch, and verify persistence outside the UI**

Use feature slug `persistence-bootstrap`; launch with `--fixture empty`, open the 题库 tab with Computer Use, capture screenshots, then run `read-state.sh`. Expected JSON: exactly one topic with `systemKind: "others"`, zero active cards and no secret-related keys.

- [ ] **Step 7: Commit the persistence base**

```bash
git add InterviewFlashcard/Core InterviewFlashcard/App InterviewFlashcardTests/Support InterviewFlashcardTests/PersistenceTests.swift
git commit -m "feat: add local persistence model"
```

### Task 3: Implement Topic and Library Management

**Files:**
- Create: `InterviewFlashcard/Features/Library/TopicService.swift`
- Create: `InterviewFlashcard/Features/Library/TopicEditorView.swift`
- Create: `InterviewFlashcard/Features/Library/LibraryView.swift`
- Create: `InterviewFlashcard/Features/Library/QuestionDetailView.swift`
- Create: `InterviewFlashcardTests/TopicServiceTests.swift`
- Modify: `InterviewFlashcard/App/RootTabView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: `TopicRecord`, `QuestionCardRecord`, `DiagnosticStateExporter`.
- Produces: `TopicService.create(name:context:)`, `rename(_:to:context:)`, `delete(_:moveCardsTo:context:)`, fixed Others entry and Topic CRUD UI.

- [ ] **Step 1: Write failing Topic rules**

```swift
@MainActor
func testTopicNamesAreTrimmedUniqueAndOthersCannotBeDeleted() throws {
    let context = try TestModelContainer.seeded().mainContext
    let service = TopicService()
    let java = try service.create(name: "  Java  ", context: context)
    XCTAssertEqual(java.name, "Java")
    XCTAssertThrowsError(try service.create(name: "java", context: context))
    let others = try XCTUnwrap(try context.fetch(FetchDescriptor<TopicRecord>()).first(where: { $0.systemKind == .others }))
    XCTAssertThrowsError(try service.delete(others, moveCardsTo: others, context: context))
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/TopicServiceTests`

Expected: compile failure because `TopicService` does not exist.

- [ ] **Step 3: Implement Topic service and UI**

Names are trimmed, non-empty, and case/diacritic-insensitive unique. Others remains fixed at the top of Library and displays its active-card count. Deleting a normal Topic requires choosing an existing destination Topic; if no alternative exists, use Others. The screen provides Create, Rename and Delete confirmations; AI is never invoked by Topic creation.

- [ ] **Step 4: Pass tests and build**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/TopicServiceTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported
```

Expected: Topic tests pass and build succeeds.

- [ ] **Step 5: Computer Use accept Topic management**

Use feature slug `topic-management`. From 题库, capture `before.png`, create `Java`, verify it appears below `待分类（Others）`, attempt duplicate `java` and observe inline validation, rename it to `JVM`, capture `after.png`, and read state. Expected: one Others and one `JVM`, no `java`, Others remains first and cannot expose a delete action.

- [ ] **Step 6: Commit Topic management**

```bash
git add InterviewFlashcard/Features/Library InterviewFlashcard/App/RootTabView.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/TopicServiceTests.swift
git commit -m "feat: add topic and library management"
```

### Task 4: Add AI Contracts, Deterministic Stub, DeepSeek Adapter, and Keychain Settings

**Files:**
- Create: `InterviewFlashcard/Core/AI/AIClient.swift`
- Create: `InterviewFlashcard/Core/AI/AISchemas.swift`
- Create: `InterviewFlashcard/Core/AI/AIResponseValidator.swift`
- Create: `InterviewFlashcard/Core/AI/RetryingAIClient.swift`
- Create: `InterviewFlashcard/Core/AI/DeepSeekAIClient.swift`
- Create: `InterviewFlashcard/Core/AI/StubAIClient.swift`
- Create: `InterviewFlashcard/Core/AI/PromptCatalog.swift`
- Create: `InterviewFlashcard/Core/Security/APIKeyStore.swift`
- Create: `InterviewFlashcard/Features/Settings/SettingsView.swift`
- Create: `InterviewFlashcardTests/AIResponseValidatorTests.swift`
- Create: `InterviewFlashcardTests/RetryingAIClientTests.swift`
- Create: `InterviewFlashcardTests/APIKeyStoreTests.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/App/RootTabView.swift`

**Interfaces:**
- Consumes: Stable `AIClient`/`APIKeyStore` signatures and `ScoringRubric`.
- Produces: all request/response DTOs, `AIResponseValidator`, `RetryingAIClient`, `DeepSeekAIClient`, `StubAIClient`, `KeychainAPIKeyStore`, Settings UI.

- [ ] **Step 1: Write failing schema and retry tests**

```swift
func testEvaluationRejectsMissingDimensionAndComputesNoModelTotal() throws {
    let response = EvaluationResponse.fixture(removing: .precision)
    XCTAssertThrowsError(try AIResponseValidator.validate(response, rubric: .general, rawText: "CAP", polishedText: "CAP theorem"))
}

func testRetryingClientRetriesOneTransientFailureOnly() async throws {
    let base = ScriptedAIClient(results: [.failure(AIError.rateLimited), .success(.fixture)])
    let sut = RetryingAIClient(base: base, maximumRetries: 1)
    _ = try await sut.decompose(.fixture)
    XCTAssertEqual(await base.callCount, 2)
}
```

- [ ] **Step 2: Run and observe missing contract failures**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AIResponseValidatorTests -only-testing:InterviewFlashcardTests/RetryingAIClientTests`

Expected: compile failure for AI DTOs and clients.

- [ ] **Step 3: Implement exact AI schemas and validation**

`DecomposeResponse` returns ordered `CandidateDraft` values with question, source-backed answer material and `SourceAnchor`; `RefineResponse` returns zero or more `RefinedCardDraft` values with merged candidate IDs, standalone question, full-score answer, topic name and source anchors. Reclassification returns only card ID/topic name. Polish returns `polishedText`, edits, suspected transcription issues and `introducedClaims`. Evaluation returns exactly six dimension values, strengths, gaps/errors, improvements, confidence, model ID, prompt version and rubric version. Validator clamps nothing: unknown topic becomes Others at the service boundary, while malformed JSON, duplicate IDs, missing anchors, empty full answer, missing/duplicate dimensions, score outside 0...100, quoted evidence absent from raw/polished text, or truncated completion is a hard response error.

- [ ] **Step 4: Implement DeepSeek transport and deterministic stub**

DeepSeek client posts to the OpenCode Go subscription endpoint `https://opencode.ai/zen/go/v1/responses` (OpenAI Responses protocol; direct `api.deepseek.com` is pay-per-use and never used), sends `Authorization: Bearer <Keychain value>`, requests JSON output, checks HTTP/finish status, and never logs request headers. Model defaults to a setting value, not a model field default. Stub output is deterministic from request IDs: sample import yields three known cards, evaluation yields dimension scores `80/60/80/80/70/100` and local total 75; launch arguments can select `success`, `transient-once`, `refine-always-fail`, `processing-paused`, `evaluation-invalid`, and `reclassify-batch-failure` modes.

- [ ] **Step 5: Implement Keychain and Settings UI**

Use Security framework generic-password service `com.gaoguobin.InterviewFlashcard.deepseek`, account `api-key`, update-or-add semantics, and delete. Settings presents SecureField, Save, Clear, configurable model text, and privacy copy stating Markdown/confirmed answer text may go to DeepSeek while audio never does. Unit tests use an in-memory `APIKeyStore`, not the user's Keychain.

- [ ] **Step 6: Pass tests, build, and Computer Use accept Settings without a real secret**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AIResponseValidatorTests -only-testing:InterviewFlashcardTests/RetryingAIClientTests -only-testing:InterviewFlashcardTests/APIKeyStoreTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported
```

Expected: all AI/Keychain tests and full suite pass, then current build launches. Use feature slug `ai-settings`, enter literal `test-key-not-valid`, save, verify masked configured state, clear, and verify not configured. State readback may expose only `apiKeyConfigured: true|false`, never the key. Do not run a real DeepSeek call in this task.

- [ ] **Step 7: Commit AI infrastructure**

```bash
git add InterviewFlashcard/Core/AI InterviewFlashcard/Core/Security InterviewFlashcard/Features/Settings InterviewFlashcard/App InterviewFlashcardTests/AIResponseValidatorTests.swift InterviewFlashcardTests/RetryingAIClientTests.swift InterviewFlashcardTests/APIKeyStoreTests.swift
git commit -m "feat: add AI and secure settings infrastructure"
```

### Task 5: Build the Overlapping Markdown Import Pipeline

**Files:**
- Create: `InterviewFlashcard/Features/Import/MarkdownChunker.swift`
- Create: `InterviewFlashcard/Features/Import/ImportCoordinator.swift`
- Create: `InterviewFlashcard/Features/Import/ImportView.swift`
- Create: `InterviewFlashcardTests/MarkdownChunkerTests.swift`
- Create: `InterviewFlashcardTests/ImportCoordinatorTests.swift`
- Create: `Tests/Fixtures/sample-interview.md`
- Create: `Tests/Fixtures/long-interview.md`
- Create: `scripts/acceptance/install-fixture.sh`
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: `AIClient.decompose`, `AIClient.refine`, import models, Topic/Others, diagnostics.
- Produces: `MarkdownChunker.chunks(markdown:configuration:)`, `ImportCoordinator.start(urls:)`, `continueRun(id:)`, and Files-based Import UI.

- [ ] **Step 1: Write failing chunk and batch tests**

```swift
func testChunkerPreservesCodeBlockAndAddsReadOnlyOverlap() throws {
    let chunks = try MarkdownChunker(configuration: .init(targetCharacters: 900, overlapCharacters: 180)).chunks(markdown: Fixtures.longMarkdown)
    XCTAssertGreaterThanOrEqual(chunks.count, 3)
    XCTAssertTrue(chunks.allSatisfy { !$0.ownedMarkdown.contains("```swift\n") || $0.ownedMarkdown.contains("\n```\n") })
    XCTAssertEqual(chunks[1].contextBefore.suffix(180), chunks[0].ownedMarkdown.suffix(180))
}

@MainActor
func testRefinementBatchesNeverMixDocumentsAndMaxAtFifty() async throws {
    let result = try await ImportCoordinator.fixture(candidateCounts: [101, 12]).makeBatches()
    XCTAssertEqual(result.map(\.candidateCount), [50, 50, 1, 12])
    XCTAssertTrue(result.allSatisfy(\.containsSingleSourceDocument))
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/MarkdownChunkerTests -only-testing:InterviewFlashcardTests/ImportCoordinatorTests`

Expected: compile failure for `MarkdownChunker` and `ImportCoordinator`.

- [ ] **Step 3: Implement structure-aware overlapping chunks**

Parse with swift-markdown into headings, paragraphs, lists, quotes, tables and fenced code blocks. Pack complete blocks up to `targetCharacters = 12000`; if one block exceeds the limit, split at paragraph/newline boundaries with `overlapCharacters = 1200`. Each `ImportChunk` stores order, heading path, owned source line range, read-only before/after context and markdown. Prompt rules allow AI to choose zero or more questions freely, but each candidate must cite source anchors and start from evidence inside the owned range; overlap is context, not a local question boundary rule.

`sample-interview.md` contains three source-backed sections (`JVM 类加载阶段`, `HashMap 扩容`, `CAP 取舍`) and one fenced Swift code block whose content includes the literal `## 这不是题目`; the stub returns exactly one candidate for each real section and none for the fenced heading. `long-interview.md` contains 52 numbered sections `Q01`...`Q52`; each has a unique question, a key-point list and a 600-character source explanation. The stub returns one candidate per section, forcing at least three 12,000-character chunks and refinement batches of 50 and 2.

- [ ] **Step 4: Implement the persistent import state machine**

The state sequence is `created → decomposing → refining → activating → completed`, with `failed` retaining the current stage/index. Copy each selected security-scoped file into Application Support before processing and create a fresh SourceDocument even if bytes match an earlier import. Process chunks in order, retry one transient error, persist candidates, then form same-document ordered batches of at most 50. Validate every refined card, map unknown topic to Others, and stage cards until every refinement batch succeeds; activate all cards in one ModelContext save. On failure, active-card count for that SourceDocument remains zero. `continueRun(id:)` resumes the failed stage without creating a new SourceDocument.

- [ ] **Step 5: Implement Files UI and progress**

Use `fileImporter` for one or more `.md` files. Show each filename, stage, completed/total chunks, completed/total refinement batches and final card count. Do not show candidate review. A failed document shows one `继续处理` action; completed documents link to generated cards. The import fixture installer resolves the current App data container and copies fixtures to `Documents/Acceptance/` so Computer Use can select them in Files.

- [ ] **Step 6: Pass import tests and build**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/MarkdownChunkerTests -only-testing:InterviewFlashcardTests/ImportCoordinatorTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported
```

Expected: chunk/batch/transaction/resume tests pass; full build succeeds.

- [ ] **Step 7: Computer Use accept a real Files import**

Use feature slug `markdown-import`. Start with only system Others, install `sample-interview.md`, capture before, tap 导入 Markdown, navigate the Simulator Files picker to On My iPhone → Interview Flashcard → Acceptance, choose the fixture, observe decomposing/refining/completed progress, open generated cards, and capture after. State must show one new SourceDocument, completed ImportRun, three active QuestionCards in Others with non-empty ReferenceAnswerVersion and source anchors. Create Topic `Java`, import the same file again, and confirm state has two independent SourceDocuments and six active cards; no reimport dedupe or linkage occurred.

- [ ] **Step 8: Computer Use accept interrupted import recovery**

Relaunch with `--ai stub --stub-mode transient-once` and verify automatic retry succeeds. Start a fresh run with `--ai stub --stub-mode refine-always-fail`, verify zero active cards for that source and a visible `继续处理`; relaunch with `--keep-data --ai stub --stub-mode success`, tap continue, and verify the same SourceDocument ID completes. Store this run under `diagnostics/mac-ui/import-recovery/`.

- [ ] **Step 9: Commit the import pipeline**

```bash
git add InterviewFlashcard/Features/Import InterviewFlashcard/Features/Library/LibraryView.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/MarkdownChunkerTests.swift InterviewFlashcardTests/ImportCoordinatorTests.swift Tests/Fixtures scripts/acceptance/install-fixture.sh
git commit -m "feat: import Markdown into refined question cards"
```

### Task 6: Add the Dedicated Others Reclassification Flow

**Files:**
- Create: `InterviewFlashcard/Features/Reclassification/ReclassificationService.swift`
- Create: `InterviewFlashcard/Features/Reclassification/OthersView.swift`
- Create: `InterviewFlashcardTests/ReclassificationServiceTests.swift`
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: `AIClient.reclassify`, `TopicRecord`, `QuestionCardRecord`, `ReclassificationRunRecord`.
- Produces: `ReclassificationService.runAllOthers(context:)` and the fixed 题库 → 待分类（Others） → AI 重新分类 path.

- [ ] **Step 1: Write failing all-Others batching behavior**

```swift
@MainActor
func testReclassificationUsesFiftyCardBatchesAndSkipsFailedBatch() async throws {
    let fixture = try ReclassificationFixture.make(othersCount: 103, topics: ["Java", "Go"])
    fixture.ai.failReclassificationCalls = [2]
    let summary = await fixture.service.runAllOthers(context: fixture.context)
    XCTAssertEqual(await fixture.ai.reclassificationBatchSizes, [50, 50, 3])
    XCTAssertEqual(summary.succeededBatches, 2)
    XCTAssertEqual(summary.failedBatches, 1)
    XCTAssertEqual(try fixture.countCards(in: .others), 50)
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/ReclassificationServiceTests`

Expected: compile failure because `ReclassificationService` does not exist.

- [ ] **Step 3: Implement the reclassification state machine**

Snapshot all active Others card IDs when the user starts; later imports do not join that run. Split into batches of at most 50. Send only card IDs, questions and the current non-Others Topic ID/name whitelist. Validate one assignment per input ID; an unknown/missing Topic maps to Others. Save each successful batch immediately and leave a failed batch unchanged, then continue. Only `topic` changes; compare question and reference-answer hashes before/after each batch in tests. Persist run/batch counts and finish with a compact success/failure summary.

- [ ] **Step 4: Implement the simple dedicated UI**

Library keeps Others fixed first with a count badge. OthersView lists the count and exposes one primary `AI 重新分类` button, no card selection and no per-batch retry. While running show completed batch count; when done show `已完成：成功 X 批，跳过 Y 批，待分类 Z 题`. If there are no user Topics, disable the action and explain that a Topic must be created first.

- [ ] **Step 5: Pass tests and Computer Use acceptance**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/ReclassificationServiceTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture reclassification-103 --ai stub --stub-mode reclassify-batch-failure --speech unsupported
```

Expected: focused/full tests and current build succeed. Use feature slug `others-reclassification`, open the fixed entry, start all-card reclassification, observe later batches continue after the injected second-batch failure, and capture completion. State must show three batch records, the first/third saved, the second failed, 50 cards still in Others, and unchanged question/answer hashes.

- [ ] **Step 6: Commit reclassification**

```bash
git add InterviewFlashcard/Features/Reclassification InterviewFlashcard/Features/Library/LibraryView.swift InterviewFlashcard/App/AppEnvironment.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/ReclassificationServiceTests.swift
git commit -m "feat: reclassify all Others cards on demand"
```

### Task 7: Implement Pure Random Single-Card Practice

**Files:**
- Create: `InterviewFlashcard/Features/Practice/QuestionDrawService.swift`
- Create: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Create: `InterviewFlashcardTests/QuestionDrawServiceTests.swift`
- Modify: `InterviewFlashcard/App/RootTabView.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: active non-trashed QuestionCards, selected Topic IDs and AnswerAttempt existence.
- Produces: `QuestionDrawService.eligibleCards(...)` and `draw(...using:)`, Practice filter state and skip/next navigation.

- [ ] **Step 1: Write failing eligibility and deterministic-random tests**

```swift
func testDefaultPoolExcludesPracticedButNotViewedOrSkippedCards() {
    let cards = Fixtures.cards(practiced: [0], viewed: [1], skipped: [2])
    let result = QuestionDrawService().eligibleCards(cards, topicIDs: Set(cards.map(\.topicID)), includePracticed: false)
    XCTAssertEqual(Set(result.map(\.id)), Set(cards.dropFirst().map(\.id)))
}

func testDrawUsesOneUniformIndexFromEntirePool() {
    var random = FixedRandomNumberGenerator(value: 2)
    let cards = Fixtures.cardSnapshots(count: 4)
    XCTAssertEqual(QuestionDrawService().draw(from: cards, using: &random)?.id, cards[2].id)
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests`

Expected: compile failure for `QuestionDrawService`.

- [ ] **Step 3: Implement Draw Pool and random selection**

`eligibleCards` filters by any selected Topic, `trashedAt == nil`, and, when `includePracticed == false`, absence of a submitted AnswerAttempt. It does not inspect view/skip events, balance Topics, weight cards, create a queue, or suppress a previously skipped card. `draw` performs exactly one `Int.random(in: 0..<count, using: &rng)` and returns nil for an empty pool.

- [ ] **Step 4: Implement the Practice UI**

The start state shows Topic multi-select and `包含已练习题` default false. `开始练习` draws one card. The answer remains hidden and only one card is rendered. `跳过` draws again without inserting an AnswerAttempt; after a completed submission, `下一题` draws again from current filters. Empty pool presents one quiet explanation plus controls to change Topic/flag.

- [ ] **Step 5: Pass tests and Computer Use acceptance**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture practice-mixed --ai stub --stub-mode success --speech unsupported --random-seed 20260804
```

Expected: focused/full tests and build succeed. Use feature slug `random-practice`; select both seeded Topics, confirm the switch is off, draw and skip the exact four IDs recorded by the seeded generator, then read state to prove every card belongs to the selected pool and attempt count is unchanged. Deselect all Topics and verify the quiet empty-pool state. Relaunch with `--keep-data --ai stub --stub-mode success --speech unsupported --random-seed 20260805`, turn on `包含已练习题`, and verify the next deterministic draw is the practiced fixture; state still has no new attempt from viewing. Capture filter, empty and card screens.

- [ ] **Step 6: Commit random practice**

```bash
git add InterviewFlashcard/Features/Practice/QuestionDrawService.swift InterviewFlashcard/Features/Practice/PracticeView.swift InterviewFlashcard/App InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/QuestionDrawServiceTests.swift
git commit -m "feat: add pure random practice flow"
```

### Task 8: Persist Text Answers Before Any AI Work

**Files:**
- Create: `InterviewFlashcard/Features/Practice/AnswerSubmissionService.swift`
- Create: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Create: `InterviewFlashcardTests/AnswerSubmissionServiceTests.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: `QuestionCardRecord`, current `ReferenceAnswerVersionRecord`, `ModelContext`.
- Produces: `AnswerSubmissionService.submitText(questionID:rawText:context:) -> AnswerAttemptRecord` and an injectable `AnswerProcessingScheduling` hook.

- [ ] **Step 1: Write failing save-before-schedule tests**

```swift
@MainActor
func testTextSubmissionSavesImmutableSnapshotsBeforeScheduling() async throws {
    let fixture = try SubmissionFixture.make()
    let attempt = try await fixture.service.submitText(questionID: fixture.card.id, rawText: "  JVM loads classes.  ", context: fixture.context)
    XCTAssertEqual(attempt.rawText, "JVM loads classes.")
    XCTAssertEqual(attempt.inputMode, .text)
    XCTAssertEqual(attempt.questionTextSnapshot, fixture.card.questionText)
    XCTAssertEqual(attempt.referenceAnswerVersion, fixture.card.currentReferenceAnswer.version)
    XCTAssertEqual(fixture.scheduler.events, [.scheduled(attempt.id)])
    XCTAssertTrue(fixture.scheduler.didObservePersistedAttempt)
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AnswerSubmissionServiceTests`

Expected: compile failure for `AnswerSubmissionService`.

- [ ] **Step 3: Implement atomic submission**

Reject whitespace-only input. Trim only leading/trailing whitespace; preserve internal content. In one save, create a submitted AnswerAttempt with question/reference-answer snapshots, input mode, raw text, submitted timestamp and processing status `polishPending`. Only after `context.save()` and diagnostic export succeed may the scheduler start processing. A successful save makes the card practiced immediately even if processing later fails. Repeated submissions append independent attempts.

- [ ] **Step 4: Implement text editing UI**

AnswerEditorView uses a multiline TextEditor, disables Submit for blank text and asks one confirmation only if processing is already underway. After submit, navigate to a processing/result screen without revealing the answer before submission. Leaving the screen must not cancel or delete the saved attempt.

- [ ] **Step 5: Pass tests and Computer Use acceptance**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AnswerSubmissionServiceTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture processing --ai stub --stub-mode processing-paused --speech unsupported --random-seed 1
```

Expected: tests/build succeed. Use feature slug `text-answer`, draw the known fixture, type `JVM 会加载 class 并做验证`, submit, immediately navigate to History before AI completion, and verify a pending attempt is visible. State must contain the exact raw text, immutable question/answer version snapshot and submitted timestamp before any PolishResult/Evaluation appears. Relaunch with `--keep-data --ai stub --stub-mode processing-paused --speech unsupported` and confirm the attempt remains.

- [ ] **Step 6: Commit text submission**

```bash
git add InterviewFlashcard/Features/Practice InterviewFlashcard/App/AppEnvironment.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/AnswerSubmissionServiceTests.swift
git commit -m "feat: persist text answer attempts"
```

### Task 9: Gate Voice Answers on Real On-Device Transcription Capability

**Files:**
- Create: `InterviewFlashcard/Core/Speech/SpeechTranscribing.swift`
- Create: `InterviewFlashcard/Core/Speech/AppleSpeechTranscriber.swift`
- Create: `InterviewFlashcard/Core/Speech/AudioRecording.swift`
- Create: `InterviewFlashcard/Features/Practice/VoiceAnswerView.swift`
- Create: `InterviewFlashcardTests/SpeechCapabilityTests.swift`
- Create: `InterviewFlashcardTests/VoiceAnswerFlowTests.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerSubmissionService.swift`
- Modify: `InterviewFlashcard/Features/Practice/AnswerEditorView.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: `SpeechTranscribing`, `AudioRecording`, AnswerSubmissionService.
- Produces: `AppleSpeechTranscriber.localCapability(locale:)`, `transcribe(fileURL:locale:)`, `M4AAudioRecorder`, and voice confirmation UI.

- [ ] **Step 1: Write failing capability and no-text rules**

```swift
func testVoiceIsUnavailableWhenRecognizerCannotRunOnDevice() async {
    let transcriber = FixtureSpeechTranscriber(capability: .unavailable(.onDeviceModelMissing))
    XCTAssertFalse(await VoiceAvailability(transcriber: transcriber).isEnabled(locale: Locale(identifier: "zh-CN")))
}

@MainActor
func testVoiceSubmissionRequiresConfirmedTranscript() async throws {
    let fixture = try VoiceFixture.make(transcript: "   ")
    await XCTAssertThrowsErrorAsync(try await fixture.submit())
    XCTAssertEqual(try fixture.attemptCount(), 0)
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/SpeechCapabilityTests -only-testing:InterviewFlashcardTests/VoiceAnswerFlowTests`

Expected: compile failure for speech types.

- [ ] **Step 3: Implement production capability detection and recording**

Request microphone and Speech authorization only after the user taps voice. For the selected locale, require an available `SFSpeechRecognizer`, authorization, and `supportsOnDeviceRecognition == true`; create `SFSpeechURLRecognitionRequest`, set `requiresOnDeviceRecognition = true`, and fail closed if the request cannot stay on device. Record mono AAC in an `.m4a` file under `Application Support/Audio/<attempt-or-draft-id>.m4a`; calculate duration, bytes and SHA-256. Never pass the file URL or bytes to AIClient.

- [ ] **Step 4: Implement disabled, recording and transcript-confirmation UI**

While capability is unavailable, show the voice button disabled with accessibility value explaining `当前设备无法本地转写`; text remains usable. In supported mode, show Start/Stop, transcribing progress, editable transcript and `使用此文字` action. Cancel removes the draft audio. Confirmed non-empty transcript is submitted through the same service as text with input mode voice, transcript snapshot and AudioAsset metadata.

- [ ] **Step 5: Pass tests and Computer Use acceptance in both injected modes**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/SpeechCapabilityTests -only-testing:InterviewFlashcardTests/VoiceAnswerFlowTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture processing --ai stub --stub-mode processing-paused --speech unsupported
```

Expected: tests/build succeed. First run feature slug `voice-gate`: verify the disabled button cannot be clicked and text input remains enabled; state contains no audio. Run a fresh `voice-permission-denied` fixture with `--speech permission-denied`, tap Voice, deny the presented test permission path, and verify Voice becomes disabled while text remains usable. Then start a fresh fixture run `voice-confirmation` with `--fixture processing --ai stub --stub-mode processing-paused --speech fixture-supported`: click record/stop, observe fixture transcript `JVM 会加载类`, edit it to `JVM 会加载并验证类`, confirm and submit. State must show one local AudioAsset relative path and the confirmed text; inspect the app container to prove the M4A exists. These Simulator checks do not count as proof of genuine on-device Speech.

- [ ] **Step 6: Commit voice capability**

```bash
git add InterviewFlashcard/Core/Speech InterviewFlashcard/Features/Practice InterviewFlashcard/App/AppEnvironment.swift InterviewFlashcardTests/SpeechCapabilityTests.swift InterviewFlashcardTests/VoiceAnswerFlowTests.swift
git commit -m "feat: add locally transcribed voice answers"
```

### Task 10: Add Separate Answer Polish and Six-Dimension Evaluation

**Files:**
- Create: `InterviewFlashcard/Features/Evaluation/AnswerProcessingService.swift`
- Create: `InterviewFlashcard/Features/Evaluation/EvaluationResultView.swift`
- Create: `InterviewFlashcardTests/AnswerProcessingServiceTests.swift`
- Create: `InterviewFlashcardTests/EvaluationResultTests.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: `AIClient.polish`, `AIClient.evaluate`, persisted AnswerAttempt snapshots and `ScoringRubric.general`.
- Produces: `AnswerProcessingService.process(attemptID:context:)`, `retry(attemptID:context:)`, persisted processing revisions and EvaluationResultView.

- [ ] **Step 1: Write failing ordering, score and failure-retention tests**

```swift
@MainActor
func testProcessingPolishesBeforeEvaluationAndComputesTotalLocally() async throws {
    let fixture = try ProcessingFixture.make(scores: .init(correctness: 80, coverage: 60, reasoning: 80, structure: 80, tradeoffs: 70, precision: 100))
    try await fixture.service.process(attemptID: fixture.attempt.id, context: fixture.context)
    XCTAssertEqual(await fixture.ai.calls, [.polish, .evaluate])
    XCTAssertEqual(try fixture.currentEvaluation().totalScore, 75)
}

@MainActor
func testFailedEvaluationKeepsAttemptAndRetryAppendsRevision() async throws {
    let fixture = try ProcessingFixture.make(failEvaluationOnce: true)
    await XCTAssertThrowsErrorAsync(try await fixture.service.process(attemptID: fixture.attempt.id, context: fixture.context))
    XCTAssertEqual(try fixture.attemptCount(), 1)
    XCTAssertEqual(try fixture.attempt().processingStatus, .evaluationFailed)
    try await fixture.service.retry(attemptID: fixture.attempt.id, context: fixture.context)
    XCTAssertEqual(try fixture.polishRevisionCount(), 2)
    XCTAssertEqual(try fixture.evaluationCount(), 1)
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AnswerProcessingServiceTests`

Expected: compile failure for `AnswerProcessingService`.

- [ ] **Step 3: Implement append-only processing**

Fetch immutable snapshots from the attempt. Polish request receives only raw answer, locale and terminology hints, never the reference answer. Save a PolishResult with raw input, polished output, edits, suspected transcription issues, introduced claims, model/prompt version and completion status. Evaluation receives question snapshot, reference-answer snapshot, raw text, polished text and fixed rubric. Validator requires correctness/coverage evidence credited by the model to quote or identify content traceable to raw text; a claim listed as introduced by polish cannot be credited in those dimensions. Compute total locally and append an Evaluation. A retry appends a new polish/evaluation processing revision and never edits raw text or old results.

- [ ] **Step 4: Implement result and failure UI**

While pending show saved status. Completed result displays raw answer, polished answer, total 0–100, all six named scores, strengths, omissions/errors, next-time improvements, confidence, model/prompt/rubric versions and the reference answer used. Failed state states that the answer is saved and offers one `重新处理`; submission already reveals the full-score answer even when AI processing failed.

- [ ] **Step 5: Pass tests and Computer Use accept success**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/AnswerProcessingServiceTests -only-testing:InterviewFlashcardTests/EvaluationResultTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture processing --ai stub --stub-mode success --speech unsupported
```

Expected: focused/full tests and build succeed. Use feature slug `ai-evaluation`. Submit `CAP 只能同时满足两个`, wait for result, expand raw/polished/reference sections and scroll through six dimensions. Expected visible scores are 80, 60, 80, 80, 70, 100 and total 75. State must contain one AnswerAttempt, one PolishResult, one Evaluation, six exact dimension keys, model/prompt/rubric versions and the same total.

- [ ] **Step 6: Computer Use accept failure and retry**

Use feature slug `answer-retry` with `--fixture processing --ai stub --stub-mode evaluation-invalid`: submit, confirm failure with saved answer, navigate away/back, relaunch with `--keep-data --ai stub --stub-mode success`, tap `重新处理`, and observe completion. State must retain one attempt, failed processing metadata, a second polish revision and one valid current evaluation.

- [ ] **Step 7: Commit answer processing**

```bash
git add InterviewFlashcard/Features/Evaluation InterviewFlashcard/Features/Practice/PracticeView.swift InterviewFlashcard/App/AppEnvironment.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/AnswerProcessingServiceTests.swift InterviewFlashcardTests/EvaluationResultTests.swift
git commit -m "feat: polish and score submitted answers"
```

### Task 11: Add Global and Per-Question Answer History

**Files:**
- Create: `InterviewFlashcard/Features/History/HistoryView.swift`
- Create: `InterviewFlashcard/Features/History/AttemptDetailView.swift`
- Create: `InterviewFlashcard/Features/History/QuestionHistoryView.swift`
- Create: `InterviewFlashcardTests/HistoryQueryTests.swift`
- Modify: `InterviewFlashcard/App/RootTabView.swift`
- Modify: `InterviewFlashcard/Features/Library/QuestionDetailView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: AnswerAttempt snapshots, current processing revision, AudioAsset and active-card soft-delete state.
- Produces: `HistoryQuery.global(topicID:questionID:)`, `forQuestion(_:)` and the global/detail/question timeline UI.

- [ ] **Step 1: Write failing history query tests**

```swift
@MainActor
func testGlobalHistoryIsNewestFirstFilterableAndHidesTrashedCards() throws {
    let fixture = try HistoryFixture.make()
    XCTAssertEqual(try fixture.query.global().map(\.id), fixture.expectedNewestFirstIDs)
    XCTAssertTrue(try fixture.query.global(topicID: fixture.javaID).allSatisfy { $0.topicID == fixture.javaID })
    XCTAssertFalse(try fixture.query.global().contains { $0.questionID == fixture.trashedCardID })
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/HistoryQueryTests`

Expected: compile failure for `HistoryQuery`.

- [ ] **Step 3: Implement queries and history screens**

Global history sorts by submittedAt descending and filters by Topic and question. Each row shows question snapshot, time, score or processing status, and input mode. Detail uses snapshots from the attempt, not the card's latest mutable text, and shows raw/polished, total/six dimensions, feedback, full-score answer, model versions and local audio playback. Question detail links to a chronological attempt timeline for comparison. Trashed cards and their attempts are hidden from normal history.

- [ ] **Step 4: Pass tests and Computer Use acceptance**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/HistoryQueryTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture history --ai stub --stub-mode success --speech unsupported
```

Expected: tests/build succeed. Use feature slug `answer-history`. Open 历史, apply the seeded Topic filter, open the newest of the two attempts on one card, verify raw/polished/scores/reference, return to the card detail and open its two-entry timeline. State IDs and version fields must match what each screen shows. The seeded voice attempt must play/pause its local recording without generating a network log.

- [ ] **Step 5: Commit history**

```bash
git add InterviewFlashcard/Features/History InterviewFlashcard/App/RootTabView.swift InterviewFlashcard/Features/Library/QuestionDetailView.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/HistoryQueryTests.swift
git commit -m "feat: add answer history and question timelines"
```

### Task 12: Add Local Review Statistics and Trends

**Files:**
- Create: `InterviewFlashcard/Features/Insights/InsightsAggregator.swift`
- Create: `InterviewFlashcard/Features/Insights/InsightsView.swift`
- Create: `InterviewFlashcardTests/InsightsAggregatorTests.swift`
- Modify: `InterviewFlashcard/App/RootTabView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: active cards, submitted attempts and current valid evaluations.
- Produces: `InsightsAggregator.snapshot(asOf:calendar:cards:attempts:) -> InsightsSnapshot` and Charts UI.

- [ ] **Step 1: Write a failing exact-metric fixture**

```swift
func testInsightsSeparatesCoverageFromAttemptCount() {
    let snapshot = InsightsAggregator().snapshot(asOf: Fixtures.august4Noon, calendar: Fixtures.shanghaiCalendar, cards: Fixtures.fourCards, attempts: Fixtures.threeAttemptsOnTwoCards)
    XCTAssertEqual(snapshot.totalCards, 4)
    XCTAssertEqual(snapshot.practicedCards, 2)
    XCTAssertEqual(snapshot.unpracticedCards, 2)
    XCTAssertEqual(snapshot.coverageRate, 0.5, accuracy: 0.0001)
    XCTAssertEqual(snapshot.answerCount, 3)
    XCTAssertEqual(snapshot.practiceDays, 2)
    XCTAssertEqual(snapshot.averageScore, 75)
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/InsightsAggregatorTests`

Expected: compile failure for `InsightsAggregator`.

- [ ] **Step 3: Implement pure local aggregation**

Calculate active total/practiced/unpracticed and coverage, answer count, distinct local-calendar practice days, 7/30-day counts, overall average, latest and best scores, six-dimension averages and time series, and per-Topic card count/coverage/average. An attempt without a valid current evaluation counts as practice/answer but not score denominator and increments an unscored count. Repeat attempts increase answer count but not practiced-card count. No aggregate cache is persisted in MVP.

- [ ] **Step 4: Implement Stats UI**

Render metric cards for coverage and attempts as separate concepts, score cards, six-dimension bar/trend charts, Topic table, recent attempts and low-score-card shortcuts. Charts expose textual accessibility summaries so Computer Use can verify exact numbers without interpreting pixels alone. Empty stats present zero state without errors.

- [ ] **Step 5: Pass tests and Computer Use acceptance**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/InsightsAggregatorTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture insights --ai stub --stub-mode success --speech unsupported
```

Expected: tests/build succeed. Use feature slug `review-statistics`; seeded data is the exact four-card/three-attempt/two-day test fixture. Open 统计 and verify visible total 4, practiced 2, unpracticed 2, coverage 50%, answers 3, days 2, average 75, dimension values and Topic rows. Scroll to trend and low-score shortcut, open it, then read state and compare with the independent unit-test fixture output saved in `tests.log`.

- [ ] **Step 6: Commit statistics**

```bash
git add InterviewFlashcard/Features/Insights InterviewFlashcard/App/RootTabView.swift InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/InsightsAggregatorTests.swift
git commit -m "feat: add local practice statistics"
```

### Task 13: Add Recoverable Trash and Explicit Permanent Deletion

**Files:**
- Create: `InterviewFlashcard/Features/Trash/TrashService.swift`
- Create: `InterviewFlashcard/Features/Trash/TrashView.swift`
- Create: `InterviewFlashcardTests/TrashServiceTests.swift`
- Modify: `InterviewFlashcard/Features/Library/LibraryView.swift`
- Modify: `InterviewFlashcard/Features/Library/QuestionDetailView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`

**Interfaces:**
- Consumes: QuestionCard relationships, history queries, AudioAsset relative paths.
- Produces: `TrashService.moveToTrash`, `restore`, `deletionImpact`, `permanentlyDelete`, and Trash UI.

- [ ] **Step 1: Write failing soft-delete/restore/cascade tests**

```swift
@MainActor
func testTrashHidesAndRestoreRecoversCardWithHistory() throws {
    let fixture = try TrashFixture.make(attempts: 2, audioAssets: 1)
    try fixture.service.moveToTrash(cardID: fixture.card.id, context: fixture.context)
    XCTAssertEqual(try fixture.history.global().count, 0)
    XCTAssertEqual(try fixture.rawAttemptCount(), 2)
    try fixture.service.restore(cardID: fixture.card.id, context: fixture.context)
    XCTAssertEqual(try fixture.history.global().count, 2)
}

@MainActor
func testPermanentDeleteRemovesAudioAfterDatabaseCommit() async throws {
    let fixture = try TrashFixture.make(attempts: 2, audioAssets: 1)
    try fixture.service.moveToTrash(cardID: fixture.card.id, context: fixture.context)
    try await fixture.service.permanentlyDelete(cardID: fixture.card.id, context: fixture.context)
    XCTAssertEqual(try fixture.rawAttemptCount(), 0)
    XCTAssertEqual(fixture.audioStore.deletedRelativePaths, [fixture.audioPath])
}
```

- [ ] **Step 2: Run and observe failure**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/TrashServiceTests`

Expected: compile failure for `TrashService`.

- [ ] **Step 3: Implement recoverable deletion**

Move-to-trash sets `trashedAt` after a confirmation and leaves all related records/files intact. Normal library, draw pool, history and stats exclude trashed cards. Restore clears `trashedAt`. `deletionImpact` fetches exact attempt/evaluation/audio counts. Permanent deletion only accepts an already-trashed ID, deletes SwiftData relationships in one save, then removes the recorded audio files; if file deletion fails, persist a cleanup log entry and retry at next launch without restoring database rows. Nothing auto-purges by age.

- [ ] **Step 4: Implement confirmations and Trash UI**

Question detail Delete alert states that card and history move to Trash. Trash supports Restore. Permanent Delete uses a second confirmation containing exact attempt and audio counts plus destructive wording; the automatic Computer Use suite must stop before tapping the final destructive action on non-fixture data.

- [ ] **Step 5: Pass tests and Computer Use accept delete/restore**

Run:

```bash
scripts/dev/test.sh -only-testing:InterviewFlashcardTests/TrashServiceTests
scripts/dev/test.sh
scripts/dev/build-and-launch.sh --fixture trash --ai stub --stub-mode success --speech unsupported
```

Expected: tests/build succeed. Use feature slug `trash-restore`. Open the seeded card with two attempts, confirm move to Trash, verify it disappears from Library/History, open Trash, restore it, and verify its history returns. State must prove `trashedAt` toggled and child IDs remained identical. Separately open the permanent-delete warning and verify exact impact counts, then cancel. Unit tests provide the cascade proof.

- [ ] **Step 6: Commit Trash**

```bash
git add InterviewFlashcard/Features/Trash InterviewFlashcard/Features/Library InterviewFlashcard/Shared/AccessibilityID.swift InterviewFlashcardTests/TrashServiceTests.swift
git commit -m "feat: add recoverable question trash"
```

### Task 14: Close the End-to-End Loop, Privacy Audit, Real Provider Smoke, and Final Sign-Off

**Files:**
- Create: `InterviewFlashcardTests/EndToEndWorkflowTests.swift`
- Create: `InterviewFlashcardTests/PrivacyBoundaryTests.swift`
- Create: `InterviewFlashcard/Core/Recovery/LaunchRecoveryCoordinator.swift`
- Create: `scripts/acceptance/run-final-checks.sh`
- Create: `docs/acceptance/mvp-signoff.md`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/App/InterviewFlashcardApp.swift`
- Modify: `docs/acceptance/iphone-offline-speech.md`

**Interfaces:**
- Consumes: all completed MVP features and acceptance tooling.
- Produces: interruption recovery on launch, final regression command, full-loop Computer Use evidence, optional real DeepSeek smoke evidence, physical-iPhone speech sign-off.

- [ ] **Step 1: Write failing end-to-end and privacy tests**

```swift
@MainActor
func testFullLocalWorkflowFromImportThroughStatistics() async throws {
    let app = try WorkflowFixture.make(ai: StubAIClient())
    let topic = try app.topics.create(name: "Java", context: app.context)
    let sourceID = try await app.importer.importFixture("sample-interview.md", context: app.context)
    let card = try XCTUnwrap(app.cards.active(sourceID: sourceID).first)
    try app.cards.move(card, to: topic, context: app.context)
    let attempt = try await app.submission.submitText(questionID: card.id, rawText: "类加载包括加载、验证和初始化", context: app.context)
    try await app.processing.process(attemptID: attempt.id, context: app.context)
    XCTAssertEqual(try app.history.global().count, 1)
    XCTAssertEqual(app.insights().practicedCards, 1)
}

@MainActor
func testLaunchRecoveryResumesImportAndPendingAttemptIdempotently() async throws {
    let fixture = try RecoveryFixture.make(interruptedImport: true, pendingAttempt: true)
    let recovery = LaunchRecoveryCoordinator(imports: fixture.importer, processing: fixture.processing, audioCleanup: fixture.audioCleanup)
    await recovery.resume(context: fixture.context)
    await recovery.resume(context: fixture.context)
    XCTAssertEqual(fixture.importer.resumeCount, 1)
    XCTAssertEqual(fixture.processing.scheduledAttemptIDs, [fixture.attemptID])
}

func testNoAIRequestContainsAudioOrAuthorizationInLogs() async throws {
    let transport = RecordingTransport()
    let client = DeepSeekAIClient(transport: transport, keyStore: InMemoryAPIKeyStore(value: "secret-marker"), model: "configured-model")
    _ = try await client.polish(.fixtureWithAudioMetadata)
    XCTAssertFalse(transport.lastBody.contains(".m4a"))
    XCTAssertFalse(transport.redactedLog.contains("secret-marker"))
}
```

- [ ] **Step 2: Run and observe workflow gaps**

Run: `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/EndToEndWorkflowTests -only-testing:InterviewFlashcardTests/PrivacyBoundaryTests`

Expected: compile failure because `LaunchRecoveryCoordinator` does not exist; privacy/workflow tests may already pass from earlier tasks.

- [ ] **Step 3: Implement launch recovery and final integration**

Implement `LaunchRecoveryCoordinator`, then call it once from App startup. It resumes import runs left in a nonterminal stage, enqueues submitted attempts in pending processing states, preserves failed attempts for explicit user retry, retries recorded orphan-audio cleanup, and never auto-starts Others reclassification. Each recovered job is idempotent by persisted stage/revision ID. Root navigation deep links from Stats/History to the correct card/attempt and handles a card moving to Trash by returning to a safe list.

- [ ] **Step 4: Implement the final check script**

`run-final-checks.sh` must run preflight, regenerate the project, run the complete test target, build Debug, launch deterministic stub/unsupported-speech mode, verify no uncommitted generated project-user files, verify every required diagnostics feature directory has the evidence filenames, scan build/launch/diagnostic text for `Authorization: Bearer`, known test key markers and absolute audio uploads, and fail non-zero on any missing/unsafe result.

- [ ] **Step 5: Run the complete deterministic Computer Use workflow**

Use feature slug `mvp-end-to-end`, uninstall the App, install the current build, and complete this exact UI path with fresh app-state reads before every action:

1. Create Topics Java and Distributed Systems.
2. Import `long-interview.md` through Files and observe at least three chunks plus two refinement batches, one containing 50 candidates.
3. Open Others and run all-card reclassification.
4. In Practice select both Topics, leave `包含已练习题` off, draw one card, skip, then draw another.
5. Submit a text answer, observe raw/polished/six scores/full-score answer, and tap 下一题.
6. Open History and the same attempt detail.
7. Open Stats and verify coverage, answer count and average.
8. Delete the answered card to Trash, verify History hides it, restore it, and verify History returns.
9. Relaunch the App and verify imported cards and attempt remain.

Capture screenshots at each major screen in addition to required before/after. `state.json` must reconcile source/card/topic/attempt/evaluation counts and IDs with the visible UI. Any mismatch fails sign-off.

- [ ] **Step 6: Run the real DeepSeek smoke test only after explicit user confirmation**

Ask for confirmation immediately before entering/saving a real API Key. After confirmation, use a neutral synthetic question and answer, save the key through Settings, run one polish/evaluate request, verify structured success, clear the key, and inspect diagnostics/logs for absence of the secret. Save evidence to `diagnostics/mac-ui/deepseek-smoke/` with request IDs and model ID but no request body containing private corpus and no key. If the user declines, mark this external smoke as not authorized rather than fabricating success; deterministic integration remains valid.

- [ ] **Step 7: Perform the physical iPhone offline-speech gate**

Install the same commit on a physical iPhone. Record device model/iOS/locale, enable airplane mode, turn Wi-Fi off, record a neutral answer, confirm visible local transcript, edit and submit, verify local M4A and the normal AI text pipeline after network is restored. Record each checkbox and screenshots in `docs/acceptance/iphone-offline-speech.md`. If no physical iPhone or signing authorization is available, leave voice final sign-off explicitly blocked while keeping the Simulator voice UI evidence; do not describe genuine local transcription as accepted.

- [ ] **Step 8: Run final checks and write sign-off**

Run:

```bash
scripts/acceptance/run-final-checks.sh
git status --short
```

Expected: all tests/build/evidence checks pass; status contains only intentionally untracked user research/prompt material, if still present. `mvp-signoff.md` records commit, Xcode version, Simulator/runtime, test count, each feature evidence path, real DeepSeek smoke disposition, physical iPhone speech disposition and remaining known limitations.

- [ ] **Step 9: Commit final integration and sign-off tooling**

```bash
git add InterviewFlashcard InterviewFlashcardTests scripts/acceptance docs/acceptance
git commit -m "test: verify interview flashcard MVP end to end"
```

## Final Definition of Done

The MVP is complete only when all of the following are true:

- Full Xcode and an iOS 26.x Simulator are pinned in the evidence; every local test and build command exits zero from the current checkout.
- All five tabs launch, and every feature in the spec's acceptance matrix has its own successful Computer Use run with before/after screenshots and independent persisted-state readback.
- The end-to-end flow creates Topics, imports long Markdown, refines candidates in same-source batches of at most 50, reclassifies Others, draws purely at random, submits and processes an answer, shows history/stats, and survives relaunch.
- Text answer raw evidence, polish revision, six dimensions, locally computed total, model/prompt/rubric versions and reference-answer snapshot remain inspectable for every completed attempt.
- Unsupported local speech disables voice while preserving text; supported test configuration completes the voice UI; real on-device offline transcription is not declared accepted without the physical-iPhone gate.
- Trash recovery preserves IDs/history/audio; permanent deletion behavior is covered by focused tests and never runs against non-fixture user data during automatic acceptance.
- Diagnostics and logs contain no API Key or uploaded audio. Real DeepSeek smoke is clearly marked completed or not authorized, never silently assumed.
- No old build, blank/covered Simulator window, missing screenshot, mismatched state, incomplete import activation or test-only acceptance is treated as success.

## Execution Order Rationale

This is one master plan because the app shell, SwiftData schema, injected AI/speech dependencies and Computer Use evidence harness are shared prerequisites. Tasks 3–13 are still reviewable vertical slices: each adds one user-visible capability, focused tests, a current-checkout build, a real Simulator path, independent state evidence and its own commit. Task 14 integrates those slices without broadening MVP scope.
