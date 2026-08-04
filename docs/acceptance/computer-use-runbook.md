# macOS Computer Use 验收手册

本手册用于从当前 checkout 构建并启动 Interview Flashcard 后，通过本机 iOS Simulator 的真实界面完成逐功能验收。单元测试、build 日志或静态截图不能单独代替这项验收。

## 通过标准

每个功能必须同时满足：聚焦测试和全量测试通过、当前 commit 构建成功、旧 App 已卸载且当前产物已安装、Computer Use 完成真实点击/输入/滚动、操作前后全屏截图存在、App container 中的诊断状态与界面一致。任何一项缺失即失败。

证据固定保存在 `diagnostics/mac-ui/<feature-slug>/`：

- `context.txt`：branch、commit、worktree、Xcode、Simulator、runtime 和 bundle ID。
- `tests.log`、`build.log`、`launch.log`：当前运行的测试、构建和启动输出。
- `steps.md`：实际用户路径、每一步可见结果、状态核对及异常。
- `before.png`、`after.png`：Computer Use 用 `Cmd+Shift+3` 触发的全屏截图。
- `state.json`：从 Simulator App container 独立读取的诊断状态。

## 八步验收合同

1. 运行 `scripts/dev/preflight.sh`。只有输出 `READY` 且生成 `.local/acceptance.env` 才能继续。运行 `scripts/acceptance/start-run.sh <feature-slug>`，确认 `context.txt` 记录的 commit 是要验收的当前 checkout。目录已有证据时脚本会拒绝覆盖；先把旧证据归档到别处再重跑。
2. 运行 `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/<SuiteName>` 并把输出保存到该功能的 `tests.log`；随后运行全量测试确认没有回归。`tests.log` 必须包含 `TEST SUCCEEDED`。
3. 运行 `scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported`。把构建和启动输出分别保存为 `build.log` 和 `launch.log`。脚本必须终止旧进程、卸载旧 App、安装当前 DerivedData 中的产物，并以 `-IFDiagnosticsEnabled YES` 启动。除需要跨启动检查持久化的验收外，不使用 `--keep-data`。
4. 在 `mcp__node_repl__js` 中只初始化一次 Computer Use runtime，然后读取 Simulator 的当前状态：

   ```javascript
   if (!globalThis.sky) {
     const { setupComputerUseRuntime } = await import("/Users/gaoguobin/.codex/plugins/cache/openai-bundled/computer-use/1.0.1000550/scripts/computer-use-client.mjs");
     await setupComputerUseRuntime({ globals: globalThis });
   }
   var simulatorState = await sky.get_app_state({ app: "Simulator" });
   nodeRepl.write(simulatorState.text);
   ```

   必须先确认前台窗口确实是 Simulator、App 界面可见且不是空白页、旧构建或系统错误对话框。
5. 每次点击、输入、滚动或按键之前，重新执行 `sky.get_app_state({ app: "Simulator" })`。只基于当次可见 label 或稳定 accessibility identifier 选择控件，不缓存和复用动态 element index。真实操作使用 `sky.click`、`sky.type_text`、`sky.press_key` 或 `sky.scroll`，不能用 shell、AppleScript 或 XCTest UI 自动化替代。
6. 首次操作前调用 `sky.press_key({ app: "Simulator", key: "super+shift+3" })`，随后运行 `scripts/acceptance/collect-screenshot.sh <feature-slug> before`。完成用户路径并确认可见结果后再次触发同一快捷键，再收集 `after`。不能以终端 `screencapture` 代替；脚本只复制运行开始后由 macOS 新生成的 PNG，并拒绝覆盖已有证据。
7. 运行 `scripts/acceptance/read-state.sh <feature-slug>`。脚本从 `xcrun simctl get_app_container "$IF_SIMULATOR_UDID" com.gaoguobin.InterviewFlashcard data` 返回的容器中读取 `Library/Application Support/Diagnostics/state.json`。把界面上的实体 ID、数量、状态、分数或配置逐项与 JSON 核对；不能只看成功提示。diagnostics 不得包含 API Key。
8. 在 `steps.md` 写明实际动作、可见结果、独立状态核对和所有异常。确认无异常后把 `- Acceptance result: PENDING` 改为 `- Acceptance result: PASS`，再运行 `scripts/acceptance/finish-run.sh <feature-slug>`。脚本检查八类证据、PNG/JSON 格式、测试和 build 成功标记、启动 bundle ID，并确认记录的 commit 与当前 checkout 完全一致。

## 失败与重跑

以下任一情况都判定失败：Xcode/Simulator 预检未通过；屏幕为空、被遮挡或显示旧版本；找不到稳定语义目标；操作未通过 Computer Use 完成；截图不是快捷键产生的完整桌面；测试、build 或 launch 失败；诊断 JSON 缺失、不可解析或与界面不一致；证据 commit 不匹配；需要系统权限、登录、上传或敏感数据输入但尚未获得用户明确许可。

失败时保留截图、日志、状态和失败步骤，把现有证据目录整体归档后修复，并从八步合同第 1 步重新执行。只清理由本次验收启动且明确属于 Interview Flashcard 的进程；不修改用户的系统设置、账户或其他 App。真实 DeepSeek smoke test 必须与确定性 stub 验收分开，并在输入或保存 API Key 前取得用户当次明确确认。
