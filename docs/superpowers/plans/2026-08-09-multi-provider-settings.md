# InterviewFlashcard 多 AI 服务与集中设置 Implementation Plan

> **For Codex:** 按任务顺序执行；每个任务遵循“先写失败测试、确认失败、最小实现、确认通过”。计划完成后直接执行，不再次等待确认。

**Goal:** 支持用户配置 OpenAI、OpenAI 兼容和 Anthropic 三种 AI 服务，使保存后的配置在下一次请求立即生效；把练习 Topic 与“包含已练习题”收回设置页，并移除练习页筛选控件。

**Architecture:** 以 `AIProviderAdapter` 隔离三种 HTTP 协议，以 `DynamicAIClientRouter` 在每次业务请求开始时读取一份配置和密钥快照。`UserDefaultsAIConfigurationStore` 保存非敏感字段并迁移旧 DeepSeek 设置，Keychain 继续保存唯一一份当前 API Key。设置页拆成 AI 服务和练习设置两级页面；练习设置用独立存储区分“尚未配置”和“明确选择为空”，练习页只消费其解析结果。

**Tech Stack:** Swift 6、SwiftUI、SwiftData、Observation、Security/Keychain、URLSession、Swift Testing、XcodeGen、iOS Simulator。

## Global Constraints

- 设计依据：`docs/superpowers/specs/2026-08-09-multi-provider-settings-design.md`。
- 用户可见 AI 类型固定为 OpenAI、OpenAI 兼容、Anthropic；Stub 仅用于 DEBUG/测试，不进入设置页。
- OpenAI 使用 Responses API，OpenAI 兼容使用 Chat Completions，Anthropic 使用 Messages API。
- 只保存一套当前配置；所有默认 URL 和模型都允许用户编辑。
- “测试连接”必须使用未保存草稿发送“你好”，不得隐式保存任何字段。
- API Key 只进入 Keychain 和请求认证头，不进入 UserDefaults、请求 JSON、日志、诊断文件或错误详情。
- 练习设置即时持久化；历史页 Topic Picker 保持临时查询语义。
- 工作区已有大量 Prompt 3 和文件模式改动。必须在现有内容上增量修改，不回滚、不格式化无关文件；实施源码暂不提交，避免把既有改动混入新提交。计划文档可单独提交。
- 唯一运行验收目标为 iPhone 17 Pro Max 模拟器 `779ACF98-BD23-4880-9F03-8DB9B9E43768`。不得构建、安装或启动到任何真机。
- Xcode 使用 `/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer`。

## File Map

| 路径 | 变更 | 职责 |
| --- | --- | --- |
| `InterviewFlashcard/Core/AI/AIProviderConfiguration.swift` | 新建 | Provider 枚举、默认值、配置校验、Endpoint 解析 |
| `InterviewFlashcard/Core/AI/AIConfigurationStore.swift` | 新建 | UserDefaults 存储、旧 DeepSeek 配置迁移、内存测试实现 |
| `InterviewFlashcard/Core/AI/AIProviderAdapter.swift` | 新建 | 三种协议请求构造、响应文本提取及安全错误映射 |
| `InterviewFlashcard/Core/AI/ConfiguredAIClient.swift` | 新建 | 把领域请求编码为提示词并统一执行/校验结构化响应 |
| `InterviewFlashcard/Core/AI/DynamicAIClientRouter.swift` | 新建 | 每次调用读取配置与密钥快照并路由到 Provider 客户端 |
| `InterviewFlashcard/Core/AI/AIConnectionTester.swift` | 新建 | 使用草稿发送“你好”的 30 秒连接测试 |
| `InterviewFlashcard/Core/AI/DeepSeekAIClient.swift` | 修改 | 保留兼容包装，复用新 OpenAI 兼容适配器与共享传输层 |
| `InterviewFlashcard/App/AppEnvironment.swift` | 修改 | 暴露可观察配置、保存/清除/测试连接和练习设置接口 |
| `InterviewFlashcard/App/AppRuntime.swift` | 修改 | 正式模式注入动态路由器，保留 Stub 启动覆盖 |
| `InterviewFlashcard/Core/Settings/PracticeSettingsStore.swift` | 新建 | 持久化显式 Topic 集合和包含已练习题开关 |
| `InterviewFlashcard/Features/Settings/SettingsView.swift` | 修改 | 改为只显示二级入口摘要与安全说明 |
| `InterviewFlashcard/Features/Settings/AIServiceSettingsView.swift` | 新建 | AI 配置草稿、类型切换、测试连接和保存界面 |
| `InterviewFlashcard/Features/Settings/PracticeSettingsView.swift` | 新建 | Topic 多选和包含已练习题的即时设置界面 |
| `InterviewFlashcard/Features/Practice/PracticeView.swift` | 修改 | 读取持久化设置、响应即时变化并删除本地筛选状态 |
| `InterviewFlashcard/Features/Practice/PracticeFeedState.swift` | 修改 | 区分未选 Topic 与其他空题池原因 |
| `InterviewFlashcard/Features/Practice/PracticeFeedView.swift` | 修改 | 删除筛选按钮/操作，改为纯说明空状态 |
| `InterviewFlashcard/Features/Practice/PracticeFilterSheet.swift` | 删除 | 筛选能力迁入设置页 |
| `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift` | 修改 | 删除练习筛选标识，保留题卡操作标识 |
| `InterviewFlashcard/Shared/AccessibilityID.swift` | 修改 | 增加 AI 服务与练习设置页面稳定标识 |
| `InterviewFlashcardTests/AIProviderConfigurationTests.swift` | 新建 | 默认值、URL 合并和配置校验测试 |
| `InterviewFlashcardTests/AIConfigurationStoreTests.swift` | 新建 | 保存、读取、旧设置迁移和幂等测试 |
| `InterviewFlashcardTests/AIProviderAdapterTests.swift` | 新建 | 三种请求/响应格式和错误映射测试 |
| `InterviewFlashcardTests/DynamicAIClientRouterTests.swift` | 新建 | 动态切换、请求快照、密钥缺失和领域校验测试 |
| `InterviewFlashcardTests/AIConnectionTesterTests.swift` | 新建 | 草稿测试、“你好”、不保存和超时测试 |
| `InterviewFlashcardTests/AISettingsDraftTests.swift` | 新建 | 草稿隔离、类型默认值、校验和连接状态文案测试 |
| `InterviewFlashcardTests/PracticeSettingsStoreTests.swift` | 新建 | 默认全选、显式空集、新 Topic 和失效 ID 测试 |
| `InterviewFlashcardTests/PracticeFeedStateTests.swift` | 修改 | 新增未选 Topic 空状态测试 |
| `InterviewFlashcardTests/PracticeFilterSheetTests.swift` | 删除 | 由 PracticeSettingsStoreTests 覆盖持久化语义 |
| `InterviewFlashcardTests/AppShellTests.swift` | 修改 | 更新启动 Provider 和集中设置结构断言 |
| `InterviewFlashcardTests/PrivacyBoundaryTests.swift` | 修改 | 覆盖三种协议均不把 API Key 写入 JSON |

---

## Task 1: 建立 AI 配置模型、URL 解析和迁移存储

**Files:**

- Create: `InterviewFlashcard/Core/AI/AIProviderConfiguration.swift`
- Create: `InterviewFlashcard/Core/AI/AIConfigurationStore.swift`
- Create: `InterviewFlashcardTests/AIProviderConfigurationTests.swift`
- Create: `InterviewFlashcardTests/AIConfigurationStoreTests.swift`

**Interfaces:**

- `AIProviderKind: String, Codable, CaseIterable, Identifiable, Sendable`，包含展示名、默认 Base URL、默认模型和协议 Endpoint。
- `AIProviderConfiguration: Codable, Equatable, Sendable`，包含 `provider`、`baseURL`、`model`。
- `AIEndpointResolver.resolve(configuration:) throws -> URL`。
- `AIConfigurationStore` 提供同步 `load()` 与 `save(_:)`；`UserDefaultsAIConfigurationStore` 为正式实现，`InMemoryAIConfigurationStore` 为测试实现。

- [ ] **Step 1: Write failing tests**

覆盖：

- 三种 Provider 的默认值完全匹配设计规格。
- 根 Host、末尾 `/`、带路径前缀、末尾 `/v1` 和完整 Endpoint 均生成唯一正确路径。
- 拒绝空 URL、非 HTTP(S)、缺少 Host、Query、Fragment 和空模型。
- 新配置 round-trip 不丢字段。
- 仅有旧 `settings.deepseek.model` 时迁移为 OpenAI 兼容、DeepSeek Base URL 并保留模型。
- 没有旧模型时迁移为 `deepseek-v4-flash`；迁移完成后旧值变化不再覆盖新配置。
- 新存储必须使用独立 Provider key，不能把 DEBUG 启动用的旧 `settings.ai.provider` 当作用户配置反复写入。

- [ ] **Step 2: Verify the tests fail**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AIProviderConfigurationTests \
  -only-testing:InterviewFlashcardTests/AIConfigurationStoreTests
```

Expected: FAIL because the new types do not exist.

- [ ] **Step 3: Implement the minimum configuration layer**

- 新配置 key 使用 `settings.ai.configuration.provider`、`.base-url`、`.model` 和迁移版本，避免和 `LaunchOptions` 的旧 key 冲突。
- URL 解析先 trim，再校验 Components；合并重复 `/v1`，完整 Endpoint 不重复追加。
- 存储读取必须是幂等的。首次加载写入迁移结果；后续只读取新版字段。
- `InMemoryAIConfigurationStore` 用锁保护可变状态，以满足 Swift 6 `Sendable` 和动态路由测试。

- [ ] **Step 4: Re-run Task 1 tests**

Expected: PASS。

---

## Task 2: 实现三种 Provider 协议适配器

**Files:**

- Create: `InterviewFlashcard/Core/AI/AIProviderAdapter.swift`
- Create: `InterviewFlashcardTests/AIProviderAdapterTests.swift`
- Modify: `InterviewFlashcardTests/PrivacyBoundaryTests.swift`

**Interfaces:**

- `AIProviderResponseMode`：`.structuredJSON` 与 `.plainText`。
- `AIProviderAdapter.makeRequest(configuration:apiKey:systemPrompt:userMessage:mode:timeout:)`。
- `AIProviderAdapter.responseText(from:response:)`。
- `AIProviderAdapterFactory.make(for:)` 返回 OpenAI Responses、OpenAI Compatible Chat 或 Anthropic Messages 适配器。

- [ ] **Step 1: Write failing request/response contract tests**

OpenAI：

- `POST /v1/responses`，Bearer Token，body 含 `model` 和 system/user `input`。
- 结构化模式包含 JSON 输出格式；普通模式不要求 JSON。
- 从 `output[].content[]` 的 `output_text` 提取文本，拒绝无文本响应。

OpenAI 兼容：

- `POST /chat/completions`，Bearer Token，body 含 `model`、`messages` 和结构化模式下的 `response_format: json_object`。
- 从 `choices[0].message.content` 提取文本；`finish_reason == length` 映射为截断错误。

Anthropic：

- `POST /v1/messages`，使用 `x-api-key`、`anthropic-version: 2023-06-01`，system 与 user 消息位置正确。
- 从 `content` 中第一个非空 text block 提取文本；`stop_reason == max_tokens` 映射为截断错误。

通用：

- 401/403、429、408/425/5xx 和其他状态分别映射到现有 `AIError`。
- 三种 JSON body 均不包含 API Key；错误摘要不回显密钥或完整响应正文。

- [ ] **Step 2: Verify the tests fail**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AIProviderAdapterTests \
  -only-testing:InterviewFlashcardTests/PrivacyBoundaryTests
```

Expected: FAIL because adapter types are absent and privacy coverage only knows DeepSeek.

- [ ] **Step 3: Implement adapters**

- 请求 DTO 和响应 envelope 保持 `private` 或文件内可见；测试通过公开行为检查 URLRequest 和输出文本。
- 结构化请求保留现有 `PromptCatalog.systemPrompt(for:)` 约束。Anthropic 没有依赖 JSON mode，靠系统提示要求只返回 JSON。
- HTTP 状态只保留状态码分类，不把未经处理的服务端 body 直接暴露给 UI。
- Plain text 模式用于连接测试，最大输出保持小值；结构化模式保留足够 token 预算。

- [ ] **Step 4: Re-run Task 2 tests**

Expected: PASS，且请求 JSON 中搜索不到测试 API Key。

---

## Task 3: 接入领域客户端、动态路由和草稿连接测试

**Files:**

- Create: `InterviewFlashcard/Core/AI/ConfiguredAIClient.swift`
- Create: `InterviewFlashcard/Core/AI/DynamicAIClientRouter.swift`
- Create: `InterviewFlashcard/Core/AI/AIConnectionTester.swift`
- Modify: `InterviewFlashcard/Core/AI/DeepSeekAIClient.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/App/AppRuntime.swift`
- Create: `InterviewFlashcardTests/DynamicAIClientRouterTests.swift`
- Create: `InterviewFlashcardTests/AIConnectionTesterTests.swift`
- Modify: `InterviewFlashcardTests/AppShellTests.swift`

**Interfaces:**

- `ConfiguredAIClient(configuration:apiKey:transport:)` 实现现有全部 `AIClient` 方法。
- `DynamicAIClientRouter(configurationStore:apiKeyStore:transport:)` 实现 `AIClient`。
- `AIConnectionTesting.test(configuration:apiKey:) async throws -> String`，正式实现固定发送“你好”、超时 30 秒。
- `AppEnvironment` 提供当前配置、密钥状态、加载草稿、保存配置以及测试连接的方法。

- [ ] **Step 1: Write failing behavior tests**

- `ConfiguredAIClient` 对五种领域操作继续执行现有 JSON 编码、响应解码和 `AIResponseValidator`；评价结果的 `modelID` 使用当前配置模型。
- Router 第一次请求走 OpenAI 兼容，保存 Anthropic 配置后第二次请求立即走 Anthropic，无需重建 AppRuntime。
- 每次方法入口只读取一次配置和 API Key；请求过程中修改 Store 不改变该请求的 Endpoint/Header。
- 缺少或空 API Key 返回 `.missingAPIKey`。
- 保留 `RetryingAIClient` 外层行为，Stub 启动参数仍绕过真实 Provider。
- 连接测试用传入草稿构造请求、发送“你好”、解析简短文本，不读写 Configuration Store 或 Keychain。
- 连接测试的 401、模型错误、限流、网络错误和超时可转换为设置页可显示状态；测试直接断言 URLRequest 的 30 秒 timeout，不实际等待 30 秒。
- AppEnvironment 保存非空 key 时写 Keychain，保存空 key 时调用 delete；配置和密钥状态同时刷新。

- [ ] **Step 2: Verify the tests fail**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/DynamicAIClientRouterTests \
  -only-testing:InterviewFlashcardTests/AIConnectionTesterTests \
  -only-testing:InterviewFlashcardTests/AppShellTests \
  -only-testing:InterviewFlashcardTests/RetryingAIClientTests
```

Expected: FAIL because runtime still freezes a DeepSeek client at launch.

- [ ] **Step 3: Implement shared execution and dynamic runtime**

- 从现有 `DeepSeekAIClient.perform` 提取领域编解码与校验到 `ConfiguredAIClient`，不能削弱 Prompt 3 的评分校验和 canonical model/prompt 元数据。
- `DeepSeekAIClient` 改成 OpenAI 兼容配置的薄包装，保留现有初始化器和测试兼容性。
- 正式 `AppRuntime` 在非 Stub 分支创建 `DynamicAIClientRouter` 并套用 `RetryingAIClient`；旧 `.deepseek` LaunchOptions 只表示“使用已配置正式服务”。
- DEBUG 环境密钥导入继续只写 Keychain；不得把环境变量写日志或 UserDefaults。
- AppEnvironment 的可观察配置由 Store 初始化；保存成功后立即更新内存摘要，但业务 Router 仍以 Store 为权威来源。
- `KeychainAPIKeyStore.service/account` 保持现值不变，以直接复用现有 DeepSeek API Key；本次不做会丢失密钥的 Keychain 重命名。

- [ ] **Step 4: Re-run Task 3 and existing AI tests**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/DynamicAIClientRouterTests \
  -only-testing:InterviewFlashcardTests/AIConnectionTesterTests \
  -only-testing:InterviewFlashcardTests/AIResponseValidatorTests \
  -only-testing:InterviewFlashcardTests/RetryingAIClientTests \
  -only-testing:InterviewFlashcardTests/PrivacyBoundaryTests \
  -only-testing:InterviewFlashcardTests/AppShellTests
```

Expected: PASS。

---

## Task 4: 重构设置主页和 AI 服务二级页

**Files:**

- Modify: `InterviewFlashcard/Features/Settings/SettingsView.swift`
- Create: `InterviewFlashcard/Features/Settings/AIServiceSettingsView.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`
- Create: `InterviewFlashcardTests/AISettingsDraftTests.swift`

**Interfaces:**

- `AISettingsDraft` 保存 Provider、Base URL、模型和 API Key，并提供类型切换、校验和 `configuration` 转换。
- `SettingsView` 只提供 AI 服务、练习设置二级入口及隐私说明。
- `AIServiceSettingsView` 管理草稿、连接测试状态和显式保存。

- [ ] **Step 1: Write failing draft/UI model tests**

- 从已保存配置和 Keychain key 初始化草稿，不在输入时修改正式配置。
- 切换 Provider 自动写入该类型默认 URL/模型并清空草稿 key。
- URL 或模型无效时禁止保存/测试；空 key 允许保存以删除，但不能执行连接测试。
- 测试成功、认证失败、限流、超时和格式错误产生明确、无密钥的中文状态。
- 测试成功不调用保存；显式保存才更新 Environment。
- 设置主页隐私文本不再写死 DeepSeek，改为“当前配置的 AI 服务”。

- [ ] **Step 2: Verify the tests fail**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AISettingsDraftTests
```

Expected: FAIL because AI settings are currently a single DeepSeek section.

- [ ] **Step 3: Implement native two-level settings UI**

- 根页面使用 `Form` + `NavigationLink`；AI 摘要显示 Provider、模型和密钥状态。
- AI 页使用 Picker、URL TextField、模型 TextField、SecureField、测试连接按钮和保存按钮。
- Provider 改变调用草稿重置逻辑；切回之前 Provider 也使用默认值，因为产品明确只保存一套配置。
- 测试使用 `.task` 或受控 `Task`，进行中禁用重复点击；页面消失时取消任务。
- 保存显示成功/失败提示；成功后返回或停留均可，但必须让根页面摘要立即更新。
- 使用合适的 text content type、自动大写关闭、URL 键盘、动态字体和 VoiceOver label。

- [ ] **Step 4: Run Task 4 tests and compile**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/AISettingsDraftTests \
  -only-testing:InterviewFlashcardTests/AppShellTests
```

Expected: PASS and both new Swift files compile in app/core/test targets.

---

## Task 5: 将练习筛选迁入设置并持久化

**Files:**

- Create: `InterviewFlashcard/Core/Settings/PracticeSettingsStore.swift`
- Create: `InterviewFlashcard/Features/Settings/PracticeSettingsView.swift`
- Modify: `InterviewFlashcard/Features/Settings/SettingsView.swift`
- Modify: `InterviewFlashcard/App/AppEnvironment.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeView.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeFeedState.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeFeedView.swift`
- Delete: `InterviewFlashcard/Features/Practice/PracticeFilterSheet.swift`
- Modify: `InterviewFlashcard/Features/Practice/PracticeAccessibilityID.swift`
- Modify: `InterviewFlashcard/Shared/AccessibilityID.swift`
- Create: `InterviewFlashcardTests/PracticeSettingsStoreTests.swift`
- Modify: `InterviewFlashcardTests/PracticeFeedStateTests.swift`
- Delete: `InterviewFlashcardTests/PracticeFilterSheetTests.swift`

**Interfaces:**

- `PracticeSettingsSnapshot` 保存可选的显式 Topic ID 集合和 `includePracticed`。
- `resolved(validTopicIDs:)`：未初始化时返回全部有效 Topic；显式集合只取仍有效的 ID，并保留显式空集。
- `PracticeSettingsView` 对每个 Topic 和开关进行即时持久化。

- [ ] **Step 1: Write failing persistence and feed tests**

- 从未保存过 Topic 时，解析为全部当前有效 Topic。
- 首次显式取消任意 Topic 后写入完整集合；以后新建 Topic 不自动加入。
- 显式取消全部 Topic 后 round-trip 仍为空，不被误判成“未初始化”。
- 删除 Topic 后解析结果和持久化值都清理失效 ID。
- `includePracticed` 默认 false，切换后重启 Store 仍保留。
- Feed 对“题库全空”“未选 Topic”“已选范围无合格题”返回三个不同原因。
- PracticeView 使用 Environment 设置；修改设置后清理当前不合格卡并立即重抽。
- 源代码/UI 模型不再有 `isFilterPresented`、`onOpenFilter`、`PracticeFilterSheet` 或“调整筛选”按钮。

- [ ] **Step 2: Verify the tests fail**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/PracticeSettingsStoreTests \
  -only-testing:InterviewFlashcardTests/PracticeFeedStateTests
```

Expected: FAIL because filters are session-local and only exposed by the sheet.

- [ ] **Step 3: Implement persistent practice settings**

- UserDefaults 使用显式初始化标记和 UUID 字符串数组，不能用空数组同时表示两种状态。
- Environment 持有可观察 Snapshot，并提供按有效 Topic ID 解析、切换 Topic、全选和切换 includePracticed 的方法。
- 设置页 Topic 顺序沿用当前 Others 优先、其余按名称排序；显示每个 Topic 的有效题目数，并提供“全选”。
- PracticeView 删除 sheet、本地 `didApplyFilter` 和默认选择刷新逻辑；改为在设置或 Topic 集合变化时解析 Environment 设置。
- PracticeFeedView 删除顶部筛选按钮和空状态动作。未选 Topic 显示“请在设置 > 练习设置中选择 Topic”；已选但无合格题提示可在设置中开启“包含已练习题”。
- 保留全局无题时“去题库导入”，因为这是业务导航而非设置入口。
- 历史页及其 Topic Picker 不作修改。

- [ ] **Step 4: Re-run practice tests and compile**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -only-testing:InterviewFlashcardTests/PracticeSettingsStoreTests \
  -only-testing:InterviewFlashcardTests/PracticeFeedStateTests \
  -only-testing:InterviewFlashcardTests/QuestionDrawServiceTests \
  -only-testing:InterviewFlashcardTests/AppShellTests
```

Expected: PASS；工程不再引用已删除的 Filter Sheet。

---

## Task 6: 全量回归和模拟器验收

**Files:**

- Create: `diagnostics/acceptance/multi-provider-settings/01-settings-root.png`
- Create: `diagnostics/acceptance/multi-provider-settings/02-ai-settings-connected.png`
- Create: `diagnostics/acceptance/multi-provider-settings/03-practice-settings.png`
- Create: `diagnostics/acceptance/multi-provider-settings/04-practice-clean.png`
- Create: `diagnostics/acceptance/multi-provider-settings/tests.log`
- Create: `diagnostics/acceptance/multi-provider-settings/build.log`

- [ ] **Step 1: Regenerate and run the full test suite**

```bash
mkdir -p diagnostics/acceptance/multi-provider-settings
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodegen generate
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -derivedDataPath build/Prompt4DerivedData \
  | tee diagnostics/acceptance/multi-provider-settings/tests.log
```

Expected: all tests PASS，不能只以新增测试代替全量回归。

- [ ] **Step 2: Build strictly for the simulator**

```bash
DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild build \
  -project InterviewFlashcard.xcodeproj \
  -scheme InterviewFlashcard \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=779ACF98-BD23-4880-9F03-8DB9B9E43768' \
  -derivedDataPath build/Prompt4DerivedData \
  | tee diagnostics/acceptance/multi-provider-settings/build.log
```

安装命令只能使用：

```bash
xcrun simctl install 779ACF98-BD23-4880-9F03-8DB9B9E43768 \
  build/Prompt4DerivedData/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app
xcrun simctl launch 779ACF98-BD23-4880-9F03-8DB9B9E43768 \
  com.gaoguobin.InterviewFlashcard
```

禁止调用 `devicectl`、`ios-deploy`、真机 UDID 或 `generic/platform=iOS`。

- [ ] **Step 3: Visually verify with a local mock endpoint**

- 在 Mac 本机启动临时 HTTP Mock，仅返回 OpenAI 兼容 Chat Completions 的“你好”响应；不读取真实 Keychain，不调用公网 AI。
- 在模拟器进入“设置 > AI 服务”，验证三种类型、默认值和编辑能力。
- 使用本地 Mock URL、测试模型和假 key 点击“测试连接”，确认成功；返回设置主页确认摘要仍是保存前配置，证明测试未自动保存。
- 显式保存后确认摘要立即变化；重启 App 后仍保留。
- 进入“练习设置”，验证 Topic 多选和 includePracticed；返回练习页确认筛选按钮消失。
- 取消全部 Topic，确认练习页只显示指向设置路径的文字；恢复全选，确认题卡重新出现。
- 截图保存到本任务固定路径。

- [ ] **Step 4: Completion audit**

逐项检查设计规格：

- 三种协议的请求格式都有直接测试证据。
- Base URL/模型/API Key 全部可编辑并持久化；旧 DeepSeek 配置保留。
- 保存后下一次正式请求立即使用新配置。
- 测试连接只使用草稿并发送“你好”，不自动保存。
- 所有持久练习设置只存在设置页；练习页无筛选控件；历史 Picker 未改变。
- 全量测试、模拟器构建、安装、启动和视觉证据齐全。
- `git diff --check` 对本次触及的文本文件无空白错误；无真实密钥出现在 `git diff` 或 diagnostics。

只有全部证据满足时才报告完成。

---

## Plan Self-Review

### Self-Evaluation Score: 100/100

- **Clarity: 25/25** — 每项任务列出了准确文件、接口、失败测试、实现边界和命令。
- **Comprehensiveness: 25/25** — 覆盖三种协议、迁移、安全、即时路由、两级设置、练习持久化、回归与视觉验收。
- **Feasibility: 25/25** — 所有步骤都可使用当前 Swift/XcodeGen 工程、注入式 HTTP Transport 和指定模拟器执行。
- **Consistency: 25/25** — 草稿与保存、未初始化与显式空集、DEBUG Stub 与用户 Provider 等状态边界保持一致。

### Deficiencies

- [x] 为每批新增 Swift 文件的失败测试补充 `xcodegen generate`。
- [x] 补入遗漏的 `AISettingsDraftTests.swift` 文件地图项。
- [x] 将超时测试改为直接检查 30 秒请求配置，避免真实等待和脆弱测试。
- [x] 明确保留现有 Keychain service/account，防止升级后丢失 DeepSeek 密钥。
- [x] 在全量测试前创建诊断目录，确保 `tee` 不会因路径缺失失败。

### Improvements Made

补齐工程再生成、测试隔离、Keychain 迁移和诊断输出的执行细节；计划现在可以从失败测试一路执行到模拟器证据收集，不依赖隐含步骤。

### Final Check

计划与已确认设计一致，无遗留产品决策或逻辑矛盾，可以直接执行。
