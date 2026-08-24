# 分享至面试闪卡 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 iOS“文件”App 可以把 `.md` 和 `.json` 用“面试闪卡”打开，并分别进入现有 Markdown AI 导入和 JSON 本地预览导入流程。

**Architecture:** 主 App 注册 Markdown/JSON 文档类型，通过 SwiftUI 外部 URL 入口接收文件。接收层把 URL 批次交给现有 `ImportView`，Markdown 复用 `ImportCoordinator`，JSON 复用 `JSONQuestionImportParser` 与 `JSONQuestionImportService`；不新增 Share Extension、App Group 或数据库迁移。

**Tech Stack:** SwiftUI, UIKit application lifecycle, SwiftData, XCTest/XCUITest, Xcode 27 iOS 27 Simulator.

## Global Constraints

- 外部文件必须在 security-scoped 访问作用域内读取；不得长期保存外部 URL 权限。
- `.md` 必须进入现有 `ImportCoordinator`，`.json` 必须进入现有 JSON 校验与预览确认，不调用 AI。
- 保持已有允许重复导入策略，不新增哈希门禁或自动去重。
- 每个功能变更必须在 iOS Simulator 上从当前 checkout 实际启动并走通一次。
- 保留现有 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace` 配置。

---

### Task 1: 注册可由系统交给 App 的文档类型

**Files:**
- Modify: `InterviewFlashcard/App/InterviewFlashcard-Info.plist`
- Test: `InterviewFlashcardTests/AppShellTests.swift`

**Interfaces:**
- Produces: 主 App 的文档类型声明，系统可将 `.md` 与 `.json` 文件路由给 `com.gaoguobin.InterviewFlashcard`。

- [ ] **Step 1: Write the failing test**

在 `AppShellTests` 增加 plist 验证，读取构建后的 Info.plist，断言存在两个 `CFBundleDocumentTypes` 项：JSON 项声明 `public.json`，Markdown 项声明自定义 Markdown UTI、扩展名 `md`，且 Markdown UTI 符合 `public.text`。

- [ ] **Step 2: Run test to verify it fails**

运行：`DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardTests/AppShellTests`

预期：新增 plist 断言失败，因为当前 Info.plist 没有 `CFBundleDocumentTypes`。

- [ ] **Step 3: Write minimal implementation**

在 Info.plist 增加 `CFBundleDocumentTypes`、JSON 的 `public.json` 声明，以及 Markdown 的 exported UTI 声明。保持现有文件共享和原有 URL 场景配置不变。

- [ ] **Step 4: Run test to verify it passes**

重新运行同一 `AppShellTests` 目标，预期新增文档类型断言通过，现有测试也通过。

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/App/InterviewFlashcard-Info.plist InterviewFlashcardTests/AppShellTests.swift
git commit -m "feat: register markdown and json document types"
```

### Task 2: 增加外部文件 URL 批次接收与路由

**Files:**
- Create: `InterviewFlashcard/Features/Import/ExternalDocumentImport.swift`
- Modify: `InterviewFlashcard/App/InterviewFlashcardApp.swift`
- Modify: `InterviewFlashcard/Features/Import/ImportView.swift`
- Test: `InterviewFlashcardTests/ExternalDocumentImportTests.swift`

**Interfaces:**
- `ExternalDocumentImportRequest`: 可观察的主 App 级待处理 URL 批次。
- `ExternalDocumentImportRouter`: 接收 URL、按后缀分组并把 security-scoped URL 交给导入视图处理；公开可测试的 URL 分类和 unsupported-file 错误。
- `ImportView(initialURLs:onInitialURLsConsumed:)`: 在已有导入页面中处理外部 URL 批次，完成后通知根视图清空请求。

- [ ] **Step 1: Write the failing tests**

在 `ExternalDocumentImportTests` 覆盖：

1. `redis.json` 被分类为 JSON，`go.md` 被分类为 Markdown，`notes.txt` 产生不支持类型错误。
2. URL 批次保持输入顺序，大小写后缀（如 `DATA.JSON`、`JAVA.MD`）按不区分大小写处理。
3. JSON 批次交给现有解析器时保留文件名，Markdown 批次交给现有协调器时保留文件名。
4. 空 URL 批次不会打开导入流程。

- [ ] **Step 2: Run test to verify it fails**

运行：`DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardTests/ExternalDocumentImportTests`

预期：失败，因为外部 URL 接收与分类类型尚不存在。

- [ ] **Step 3: Write minimal implementation**

在 App 根视图添加 `.onOpenURL` 接收入口，把每次 URL 合并到待处理批次；冷启动时待处理批次在服务准备完成后再交给导入页面。导入页面接收批次后复用现有 `start(urls:)` 与 `readJSON(urls:)` 路径，确保每次读取外部 URL 时调用 `startAccessingSecurityScopedResource()`，读取结束后成对停止访问。外部文件不直接持久化 security-scoped URL。

路由层只按文件扩展名决定业务，不复制 Markdown AI 逻辑或 JSON 解析逻辑。外部请求展示与现有导入页面相同的 Markdown 任务状态、JSON 预览和错误提示。

- [ ] **Step 4: Run test to verify it passes**

重新运行 `ExternalDocumentImportTests`，预期分类、文件名保留、空批次和不支持后缀测试通过；同时运行 `AppShellTests`，确保根视图和现有启动参数测试不回归。

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcard/Features/Import/ExternalDocumentImport.swift InterviewFlashcard/App/InterviewFlashcardApp.swift InterviewFlashcard/Features/Import/ImportView.swift InterviewFlashcardTests/ExternalDocumentImportTests.swift
git commit -m "feat: route external documents into import flows"
```

### Task 3: 覆盖冷启动、前台和多文件导入行为

**Files:**
- Modify: `InterviewFlashcardTests/ExternalDocumentImportTests.swift`
- Modify: `InterviewFlashcardUITests/JSONImportUITests.swift`
- Create: `InterviewFlashcardUITests/ExternalDocumentImportUITests.swift`

**Interfaces:**
- Produces: 可重复的模拟器验收入口，验证系统打开文件 URL 后两种业务均能落到现有 UI 和数据状态。

- [ ] **Step 1: Write the failing tests**

增加 UI 测试场景：

1. 以测试 fixture 启动 App，打开一个有效 JSON 外部文件 URL，验证 JSON 预览出现，确认后出现导入成功摘要。
2. 打开一个 Markdown 外部文件 URL，验证导入记录出现且状态为待处理/后台处理中，不要求测试调用真实 AI。
3. 一次打开 JSON 与 Markdown 两个 URL，验证两种文件分别进入对应路径。
4. 打开无效 JSON，验证错误提示且题目数量不增加。

- [ ] **Step 2: Run test to verify it fails**

运行：`DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardUITests/ExternalDocumentImportUITests`

预期：失败，因为当前 App 尚未处理系统文件 URL。

- [ ] **Step 3: Write minimal implementation**

为 UI 测试准备仅用于测试的 app-container fixture 写入方式；测试通过 `simctl` 将 fixture 放入当前安装 App 的 `Documents`，再用 `simctl openurl file://...` 触发系统文档打开路径。生产代码不增加测试专用的自动导入开关，仍通过真实外部 URL 接收流程执行。

- [ ] **Step 4: Run test to verify it passes**

先运行目标 UI 测试，再运行完整相关测试集合：

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' -only-testing:InterviewFlashcardTests -only-testing:InterviewFlashcardUITests
```

预期：单元测试和 UI 测试通过；模拟器实际显示 JSON 预览和 Markdown 导入记录。

- [ ] **Step 5: Commit**

```bash
git add InterviewFlashcardTests/ExternalDocumentImportTests.swift InterviewFlashcardUITests/JSONImportUITests.swift InterviewFlashcardUITests/ExternalDocumentImportUITests.swift
git commit -m "test: verify external markdown and json imports"
```

### Task 4: 运行最终验收并记录结果

**Files:**
- Modify: `docs/superpowers/plans/2026-08-24-share-to-interview-flashcard.md` (check off completed steps and record commands/results)
- Modify: `docs/superpowers/specs/2026-08-24-share-to-interview-flashcard-design.md` only if implementation exposes a design mismatch

- [ ] **Step 1: Build from the current checkout**

用 Xcode Beta 的 `DEVELOPER_DIR` 构建主 App 和测试目标，确认 plist 文档注册、外部 URL 路由和现有 SwiftData 模型均能编译。

- [ ] **Step 2: Exercise the changed flows in the iOS Simulator**

在 iOS 27 Simulator 上实际打开 `.json` 和 `.md` fixture，分别完成 JSON 预览确认和 Markdown 导入任务创建；记录模拟器 UDID、fixture 名称和最终 UI 状态。

- [ ] **Step 3: Run focused regression tests**

运行 JSON 导入、Markdown 导入、AppShell、外部 URL 路由和 UI 测试；检查 `git diff --check`，确保不修改用户已有的无关工作区变更。

- [ ] **Step 4: Commit final verification notes**

```bash
git add docs/superpowers/plans/2026-08-24-share-to-interview-flashcard.md
git commit -m "test: verify share document import flow"
```
