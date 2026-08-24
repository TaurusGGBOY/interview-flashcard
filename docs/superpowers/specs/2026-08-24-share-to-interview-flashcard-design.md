# 分享至面试闪卡：Markdown 与 JSON 文档接收设计

日期：2026-08-24

## 目标

让用户在 iOS“文件”App 中选择 `.md` 或 `.json` 文件后，可以通过“分享”或“用其他 App 打开”选择“面试闪卡”。主 App 接收文件后按文件类型进入已有的两条导入业务：Markdown 走 AI 后台导入，JSON 走本地校验和预览确认。

本方案不新增 Share Extension，不引入 App Group，也不迁移现有 SwiftData 数据库。

## 用户流程

```text
文件 App
  -> 选择一个或多个 .md/.json
  -> 分享 / 用其他 App 打开
  -> 选择“面试闪卡”
  -> 面试闪卡接收文件并复制到自己的暂存目录
  -> 按扩展名分流
```

Markdown 文件进入现有 `ImportCoordinator`，创建持久化导入任务并继续由现有后台恢复机制处理。接收成功后立即返回题库页面，用户不需要等待 AI 请求完成。

JSON 文件进入现有 `JSONQuestionImportParser`。所有文件校验通过后展示已有 JSON 预览界面；用户确认后调用现有批量 JSON 导入服务。JSON 不调用 AI，也不重复请求满分答案。

## 系统集成

### 文档类型注册

在主 App 的 Info.plist 注册：

- `.json`，使用系统 JSON UTI；
- `.md`，注册 Markdown 文本 UTI，声明扩展名 `md`、MIME 类型 `text/markdown`，并声明其符合 `public.text`。

文档角色为 Editor，使系统可以在“文件”App 的“用其他 App 打开”或分享目的地中显示“面试闪卡”。保持现有 `UIFileSharingEnabled` 和 `LSSupportsOpeningDocumentsInPlace` 配置。

### 外部文件路由

在 SwiftUI App 的主入口增加统一 URL 接收层，覆盖冷启动、前台和后台恢复场景。接收到的 URL 不直接长期保存 security-scoped URL；先在安全访问作用域内读取并复制到 App 自己的暂存目录，然后再启动异步业务处理。

外部接收层向 `AppRuntime` 提交文件批次。`AppRuntime` 负责在服务已初始化后分流，避免 App 冷启动时导入服务尚未准备完成。多个 URL 保持用户选择顺序；每个文件独立记录文件名和错误。

## 分流与错误策略

- 后缀不属于 `md` 或 `json`：拒绝该文件并提示支持范围。
- JSON 解析或字段校验失败：不创建导入记录，错误包含文件名和 JSON 字段路径。
- Markdown 读取或编码失败：该文件失败，不影响同批其他文件。
- 多文件批次允许部分成功；成功文件的持久化记录不因另一文件失败而回滚。
- App 退出或被系统终止时，Markdown 已创建的导入记录仍由现有恢复机制继续；尚未复制完成的外部文件只报告失败。
- 已有的重复导入策略保持不变，不新增哈希门禁或自动去重。这样不会改变现有“允许用户重新导入”的行为。

## 代码边界

- Info.plist：只负责声明系统可交给 App 的文件类型。
- 外部文件接收层：只负责接收 URL、security-scoped 访问和暂存。
- `AppRuntime`：负责启动后接收队列和按扩展名分流。
- `ImportCoordinator`：继续负责 Markdown 的任务创建、AI 处理和恢复。
- `JSONQuestionImportParser` / `JSONQuestionImportService`：继续负责 JSON 校验、预览后的确认和本地导入。
- 现有 `ImportView`：复用既有 Markdown 任务状态和 JSON 预览 UI；仅增加外部文件批次进入这些入口的能力。

## 测试与验收

增加自动化测试覆盖：

1. Info.plist 声明 `.md` 和 `.json` 文档类型。
2. 外部 `.md` URL 路由到 Markdown 导入协调器。
3. 外部 `.json` URL 路由到 JSON 校验和预览数据。
4. 无效 JSON 不创建导入记录。
5. 多文件批次保留独立文件名和部分失败结果。

在 iOS Simulator 上从“文件”目录打开测试 `.md` 和 `.json` 文件，确认系统显示“面试闪卡”，并分别验证：Markdown 创建后台导入任务；JSON 显示预览并确认后新增题目。最终报告模拟器型号、构建命令和实际交互结果。

## 不在本次范围内

- 不新增 Share Extension 或 App Group。
- 不实现局域网传输。
- 不改变 Markdown 的 AI 提取规则。
- 不改变 JSON 格式、评分逻辑或重复导入策略。
