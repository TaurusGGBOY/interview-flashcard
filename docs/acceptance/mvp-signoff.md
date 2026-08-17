# InterviewFlashcard MVP 签收状态

## 结论

截至当前 checkout，代码、测试、构建、安装启动和独立诊断读回已完成；MVP **尚未最终签收**。原因不是代码测试失败，而是本机的 macOS Computer Use 无法看到或控制 iOS Simulator 的窗口，因而不能诚实地产生计划要求的真实 UI 截图/点击证据。物理 iPhone 的离线转写也尚未执行。

## 可复核环境

- commit：`e908cc39636635c8f219c6869cfd51d81e5c968d`
- Xcode：`27.0 (27A5228h)`，路径 `/Users/gaoguobin/Downloads/Xcode-beta.app`
- Simulator：`iPhone 17 Pro Max`，UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`
- Runtime：`iOS 27.0`；App deployment target 仍为 iOS 26.0
- bundle：`com.gaoguobin.InterviewFlashcard`
- AI：确定性本地 Stub；未输入或保存真实 DeepSeek API Key

## 已完成的可复核检查

| 检查 | 结果 | 证据 |
|---|---|---|
| 完整 XCTest | PASS，65/65 | `.build/logs/full-tests.command.log` |
| 端到端导入→回答→润色→评分→统计 | PASS，3/3 新增测试 | `.build/logs/new-tests.command.log`、`InterviewFlashcardTests/EndToEndWorkflowTests.swift` |
| DeepSeek 请求隐私边界 | PASS，1/1 | `InterviewFlashcardTests/PrivacyBoundaryTests.swift` |
| Debug build、卸载旧包、安装当前产物并启动 | PASS | `.build/logs/final-build.log`、`.build/logs/final-launch.log` |
| 诊断状态独立读回 | PASS | Simulator App Container `Library/Application Support/Diagnostics/state.json` |
| 运行时进程 | PASS | `simctl launch` 后 `InterviewFlashcard` 进程存活，无崩溃对话框 |

当前诊断快照已读回：3 张题、1 次 typed 回答、1 个 polish revision、1 个 completed evaluation，六维分数与本地总分 75 均存在；无音频资产、无 API Key 字段。

## 尚未签收的硬门槛

| 功能 | 要求的证据目录 | 状态 |
|---|---|---|
| App shell / persistence | `diagnostics/mac-ui/app-shell/` | BLOCKED：Simulator UI 不可见 |
| Markdown import / 50-item batches | `diagnostics/mac-ui/markdown-import/` | BLOCKED：Simulator UI 不可见 |
| 随机抽题 / 已练习开关 | `diagnostics/mac-ui/practice-random/` | BLOCKED：Simulator UI 不可见 |
| 文字润色 / 六维评分 | `diagnostics/mac-ui/text-answer/` | BLOCKED：Simulator UI 不可见 |
| 本地语音能力门控与录音 UI | `diagnostics/mac-ui/voice-answer/` | BLOCKED：Simulator UI 不可见；物理机也未验收 |
| 全局及单题历史 | `diagnostics/mac-ui/answer-history/` | BLOCKED：Simulator UI 不可见 |
| 复习统计 | `diagnostics/mac-ui/review-statistics/` | BLOCKED：Simulator UI 不可见 |
| 回收站恢复/永久删除确认 | `diagnostics/mac-ui/trash-restore/` | BLOCKED：Simulator UI 不可见 |
| 完整 UI 端到端路径 | `diagnostics/mac-ui/mvp-end-to-end/` | BLOCKED：Simulator UI 不可见 |

之前 `sky.list_apps()` 只显示 Xcode 和其他 macOS 应用，没有旧的 `Simulator`；这是 Xcode 27 将 Simulator UI 合并到 Device Hub 后的识别差异。现在已确认可用目标是 Device Hub bundle `com.apple.dt.Devices`，并能读到 iPhone 17 Pro Max 的 accessibility tree；后续验收统一使用该目标，不再使用其他 Simulator。

## 外部能力处置

- DeepSeek smoke：未授权，未保存真实密钥；确定性 Stub 已覆盖结构化响应与隐私边界。
- 物理 iPhone 离线 Speech：未执行。按 [iphone-offline-speech.md](./iphone-offline-speech.md) 保持 BLOCKED，不把 Simulator fixture 当成真实离线转写证明。

## 严格最终检查

`run-final-checks.sh` 会运行 preflight、全量测试、构建启动、隐私扫描，并强制要求每个 Computer Use 证据目录包含 `context.txt`、`tests.log`、`build.log`、`launch.log`、`steps.md`、`before.png`、`after.png`、`state.json`。当前这些目录尚未产生，因此脚本会以非零状态报告 `BLOCKED`；这是预期的安全失败，不是“通过”。

恢复 Simulator 的可见 Computer Use 窗口后，应从 [computer-use-runbook.md](./computer-use-runbook.md) 第 1 步重新执行每个 feature slug，完成证据后再运行严格最终检查。
