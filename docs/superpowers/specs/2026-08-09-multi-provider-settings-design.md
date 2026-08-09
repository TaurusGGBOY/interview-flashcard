# 多 AI 服务与集中设置设计

## 目标

- 将当前仅支持 DeepSeek 的配置扩展为三种用户可选类型：OpenAI、OpenAI 兼容、Anthropic。
- URL、模型和 API Key 均允许用户编辑；切换类型时自动填入该类型的默认 URL 与模型。
- 按服务商协议发送现有出题、评分等 AI 请求，并提供使用未保存草稿的“测试连接”功能。
- 保存后的 AI 配置立即影响下一次请求，无需重新启动应用。
- 将持久化的练习筛选设置集中到设置页，移除练习页中的筛选控件，让业务页面保持简洁。
- 保留现有 DeepSeek 配置和密钥，升级后无需重新录入。

## 已确认的产品边界

- 应用只保存一套当前生效的 AI 配置，不为每一种类型保存独立账号档案。
- 用户填写的是 Base URL，应用负责补齐当前协议的请求路径。
- OpenAI 使用 Responses API；OpenAI 兼容使用 Chat Completions API；Anthropic 使用 Messages API。
- “测试连接”发送“你好”，使用页面当前尚未保存的草稿；成功不会自动保存。
- 练习 Topic 选择和“包含已练习题”是全局持久化设置。
- 练习页移除筛选按钮和筛选弹窗；历史页 Topic Picker 是临时查询条件，继续保留。
- 最终安装、启动和视觉验收只在 iOS 模拟器进行，除非用户另行明确要求，不安装到真机。

## 配置模型与默认值

新增用户可见的 `AIProviderKind`：

| 类型 | 默认 Base URL | 默认模型 | 请求路径 |
| --- | --- | --- | --- |
| OpenAI | `https://api.openai.com` | `gpt-5.6-terra` | `/v1/responses` |
| OpenAI 兼容 | `https://api.deepseek.com` | `deepseek-v4-flash` | `/chat/completions` |
| Anthropic | `https://api.anthropic.com` | `claude-sonnet-5` | `/v1/messages` |

默认模型依据实现时的官方模型说明选择；它们只是初始值，用户可以自由修改。OpenAI 的模型与 Responses API 以 [OpenAI Models](https://developers.openai.com/api/docs/models) 和 [OpenAI API Quickstart](https://platform.openai.com/docs/quickstart/make-your-first-api-request) 为准；Anthropic 的模型与 Messages API 以 [Anthropic Models](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions) 和 [Messages API](https://platform.claude.com/docs/en/api/messages) 为准；OpenAI 兼容默认值继续采用 [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion)。

`AIProviderConfiguration` 保存类型、Base URL 和模型。非敏感字段写入 `UserDefaults`；API Key 继续由 `APIKeyStore` 存入 Keychain。Stub 客户端只用于测试和启动参数覆盖，不显示在用户可选类型中。

## 动态路由与协议适配器

新增动态 AI 客户端路由器。出题、评分等业务服务仍只依赖现有 `AIClient` 抽象；路由器在每次请求开始时读取一份最新的已保存配置快照，再创建或选择对应协议适配器：

- `OpenAIResponsesAIClient`：把系统指令和用户输入转换为 Responses API 的 `model`、`input` 等字段，使用 `Authorization: Bearer <key>`，并从 Responses 输出内容中提取文本。
- `OpenAICompatibleAIClient`：沿用并泛化现有 DeepSeek Chat Completions 实现，发送 `model`、`messages` 和兼容的结构化输出参数，使用 Bearer Token，并读取 `choices[0].message.content`。
- `AnthropicMessagesAIClient`：把系统提示放入顶层 `system`，用户消息放入 `messages`，使用 `x-api-key`、`anthropic-version: 2023-06-01` 和 JSON Content-Type，并从 `content` 文本块提取结果。

三种适配器最终都返回应用已有的领域响应类型。现有响应校验器继续负责 JSON 解码、业务字段检查和错误归一化，避免协议差异扩散到导入、评分和重新分类流程。

保存设置时更新配置存储。由于动态路由器按请求读取快照，下一次请求立即使用新配置；已经发出的请求继续使用启动时取得的旧快照，避免请求执行中途切换 URL 或密钥。

## URL 解析

URL 解析器先去除首尾空白和末尾斜杠，再验证 Scheme 只能是 `http` 或 `https`，且必须包含 Host。查询参数和 Fragment 不作为 Base URL 接受。

解析器保留自定义代理的路径前缀，并处理以下常见输入：

- Host 根地址：直接追加完整协议路径。
- 以 `/v1` 结尾的代理地址：合并重复的 `/v1` 后追加资源名。
- 已包含当前完整请求路径的地址：直接使用，避免重复拼接。

这样既能使用默认地址，也支持用户输入带路径前缀的自建 OpenAI 兼容网关。

## 设置页信息架构

设置主页使用原生分组列表和二级导航，只显示摘要：

- **AI 服务**：显示当前类型、模型和是否已配置 API Key。
- **练习设置**：显示已选 Topic 数量和是否包含已练习题。
- **安全与隐私**：保留 API Key 仅存储在设备 Keychain 等说明。

### AI 服务页

AI 服务页包含类型选择、Base URL、模型、SecureField API Key、“测试连接”和“保存”：

- 进入页面时，把已保存配置复制为可编辑草稿。
- 切换类型时，用该类型默认值替换草稿 URL 和模型，并清空草稿 API Key，避免把旧服务密钥误发给新服务。
- 离开或取消页面不会修改已保存配置。
- 保存时校验类型、URL 和模型；API Key 允许为空，保存空密钥会删除 Keychain 中的旧密钥。
- 保存成功后更新页面摘要，并立即影响下一次正式 AI 请求。
- 输入控件使用合适的键盘、自动填充与无障碍标签；密钥默认隐藏，不出现在日志或错误文本中。

### 测试连接

“测试连接”不依赖已保存配置，而是从当前草稿构造临时客户端，发送单条用户消息“你好”：

- 测试请求不要求业务 JSON 输出，也不会触发出题或评分。
- 收到 HTTP 成功响应且可按对应协议解析时，即判定连接成功；若存在文本，可在成功提示中显示简短摘要。
- 测试期间显示进度并禁止重复触发，默认超时 30 秒。
- 测试成功或失败均不保存草稿。
- 错误归类为 URL 无效、认证失败、模型不可用、限流、超时、网络异常和响应格式错误，并显示可操作的简短说明。

## 练习设置与练习页

二级“练习设置”页提供 Topic 多选和“包含已练习题”开关：

- 首次没有持久化记录时，选择全部现有有效 Topic；“包含已练习题”默认关闭。
- 练习设置采用即时持久化；一旦用户首次修改选择，后续新建 Topic 不自动加入该集合。
- 删除 Topic 后，自动忽略并清理失效 ID。
- 允许取消全部 Topic；这是有效设置，而不是“尚未初始化”。
- 设置变化后，练习数据源使用最新 Topic ID 集合和包含已练习题开关。

练习页删除筛选按钮、`PracticeFilterSheet` 展示入口和空状态中的“调整筛选”操作。没有选择 Topic 时，页面只显示“请在设置 > 练习设置中选择 Topic”的说明，不在业务页重新放置设置控件。历史页 Topic Picker 继续作为当前搜索会话的临时范围，不写入练习设置。

## 兼容性与迁移

首次读取新版配置时执行幂等迁移：

- 现有 DeepSeek provider 映射为 OpenAI 兼容。
- Base URL 使用 `https://api.deepseek.com`。
- 保留已有 DeepSeek 模型；没有值时使用 `deepseek-v4-flash`。
- 继续读取现有 Keychain service/account 中的 API Key，避免用户重新录入。
- 写入新版迁移标记；之后不再用旧值覆盖用户保存的新配置。

若配置缺失或无效，设置页仍可正常打开并显示默认草稿；正式 AI 请求返回“尚未完成配置”类错误，不回退到未知服务或静默使用 Stub。

## 错误、安全与并发

- API Key 不写入 `UserDefaults`、诊断导出、请求日志或 UI 错误详情。
- 服务端错误正文只提取安全摘要；认证头和完整请求不进入日志。
- 每次正式请求持有不可变配置快照，保存设置不会破坏进行中的请求。
- 现有 `RetryingAIClient` 继续处理可重试的瞬时错误；认证、URL 和协议解码错误不盲目重试。
- 测试连接使用独立临时客户端，不替换正式路由器状态，也不与保存操作绑定。

## 验证与验收

单元测试覆盖：

- 三种默认配置、URL 规范化、`/v1` 合并和完整路径去重。
- 三种协议的请求方法、路径、请求头、请求体和响应文本解析。
- 错误状态映射以及错误和日志不泄露 API Key。
- 配置存储、密钥保存/删除、DeepSeek 旧数据迁移及迁移幂等性。
- 保存配置后下一次请求立即切换，而进行中的请求继续使用旧快照。
- 测试连接读取未保存草稿、发送“你好”且不修改正式配置。
- Topic 默认选择、显式空选择、新 Topic 行为、失效 ID 清理和包含已练习题开关。

集成和界面测试覆盖：

- 设置主页二级导航及摘要更新。
- 切换类型自动填入默认 URL/模型并清空密钥草稿。
- 测试连接的加载、成功和主要错误状态。
- 练习页不再显示筛选入口，并正确应用持久化设置。
- 未选择 Topic 时显示指向设置路径的纯提示空状态。
- 历史页 Topic Picker 行为保持不变。

网络测试使用 URL 拦截或本地 Mock，不擅自使用用户真实 API Key。完成后运行完整测试套件，并仅在已启动的 iOS 模拟器中构建、安装、启动和视觉检查设置页与练习页。

## 非目标

- 不保存多套服务商配置，也不提供账号/profile 切换。
- 不在本次工作中加入自定义请求头、组织 ID、代理认证或高级采样参数。
- 不把历史页等临时查询筛选迁移成全局设置。
- 不自动测试或轮询真实 AI 服务。
