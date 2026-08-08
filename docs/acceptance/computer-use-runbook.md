# macOS Computer Use 验收手册

本手册用于从当前 checkout 构建并启动 Interview Flashcard 后，通过 Xcode 27 的 Device Hub 中 iPhone 17 Pro Max Simulator 真实界面完成逐功能验收。单元测试、build 日志或静态截图不能单独代替这项验收。

## 通过标准

每个功能必须同时满足：聚焦测试和全量测试通过、当前 commit 构建成功、旧 App 已卸载且当前产物已安装、Computer Use 完成真实点击/输入/滚动、操作前后全屏截图存在、App container 中的诊断状态与界面一致。任何一项缺失即失败。

针对 iPhone 17 Pro Max，额外要求编译产物通过 `scripts/acceptance/assert-iphone-app-metadata.sh`：`UILaunchScreen`、`UIApplicationSceneManifest` 必须存在，`UIDeviceFamily` 只能包含 iPhone，portrait orientation 必须存在。应用背景应覆盖整个 440 × 956 pt 安全区外表面；题干、按钮、导航和键盘操作必须留在 safe area 内。不得用固定 440/956 尺寸或把交互内容延伸到 Dynamic Island/home indicator 下方。

证据固定保存在 `diagnostics/mac-ui/<feature-slug>/`：

- `context.txt`：branch、commit、worktree、Xcode、Simulator、runtime 和 bundle ID。
- `tests.log`、`build.log`、`launch.log`：当前运行的测试、构建和启动输出。
- `steps.md`：实际用户路径、每一步可见结果、状态核对及异常。
- `before.png`、`after.png`：Computer Use 用 `Cmd+Shift+3` 触发、由收集脚本归档后删除源文件的全屏截图。
- `state.json`：从 Simulator App container 独立读取的诊断状态。

## 八步验收合同

1. 运行 `scripts/dev/preflight.sh`。只有输出 `READY` 且生成 `.local/acceptance.env` 才能继续。运行 `scripts/acceptance/start-run.sh <feature-slug>`，确认 `context.txt` 记录的 commit 是要验收的当前 checkout。目录已有证据时脚本会拒绝覆盖；先把旧证据归档到别处再重跑。
2. 运行 `scripts/dev/test.sh -only-testing:InterviewFlashcardTests/<SuiteName>` 并把输出保存到该功能的 `tests.log`；随后运行全量测试确认没有回归。`tests.log` 必须包含 `TEST SUCCEEDED`。
3. 运行 `scripts/dev/build-and-launch.sh --ai stub --stub-mode success --speech unsupported`。把构建和启动输出分别保存为 `build.log` 和 `launch.log`。脚本必须终止旧进程、卸载旧 App、安装当前 DerivedData 中的产物，并以 `-IFDiagnosticsEnabled YES` 启动。除需要跨启动检查持久化的验收外，不使用 `--keep-data`。
   脚本在安装前会调用 `scripts/acceptance/assert-iphone-app-metadata.sh`；元数据断言失败时不得继续安装。
4. Xcode 27 不再提供旧的独立 `Simulator.app`；Simulator 画面由 Device Hub 承载。先在 Xcode 中选择 `Xcode > Open Developer Tool > Device Hub`，然后在 `mcp__node_repl__js` 中只初始化一次 Computer Use runtime，并读取 Device Hub 的当前状态：

   ```javascript
   if (!globalThis.sky) {
     const { setupComputerUseRuntime } = await import("/Users/gaoguobin/.codex/plugins/cache/openai-bundled/computer-use/1.0.1000550/scripts/computer-use-client.mjs");
     await setupComputerUseRuntime({ globals: globalThis });
   }
   var simulatorState = await sky.get_app_state({ app: "com.apple.dt.Devices" });
   nodeRepl.write(simulatorState.text);
   ```

   必须先确认前台窗口确实是 Device Hub，左侧选中唯一的 `iPhone 17 Pro Max`（UDID `779ACF98-BD23-4880-9F03-8DB9B9E43768`），App 界面可见且不是空白页、旧构建或系统错误对话框。
5. 每次点击、输入、滚动或按键之前，重新执行 `sky.get_app_state({ app: "com.apple.dt.Devices" })`。只基于当次可见 label 或稳定 accessibility identifier 选择控件，不缓存和复用动态 element index。真实操作使用 `sky.click`、`sky.type_text`、`sky.press_key` 或 `sky.scroll`，不能用 shell、AppleScript 或 XCTest UI 自动化替代。
6. 首次操作前调用 `sky.press_key({ app: "com.apple.dt.Devices", key: "super+shift+3" })`，随后运行 `scripts/acceptance/collect-screenshot.sh <feature-slug> before`。完成用户路径并确认可见结果后再次触发同一快捷键，再收集 `after`。不能以终端 `screencapture` 代替；脚本只复制运行开始后由 macOS 新生成的 PNG，验证归档成功后删除桌面上的源 PNG，并拒绝覆盖已有证据。
7. 运行 `scripts/acceptance/read-state.sh <feature-slug>`。脚本从 `xcrun simctl get_app_container "$IF_SIMULATOR_UDID" com.gaoguobin.InterviewFlashcard data` 返回的容器中读取 `Library/Application Support/Diagnostics/state.json`。把界面上的实体 ID、数量、状态、分数或配置逐项与 JSON 核对；不能只看成功提示。diagnostics 不得包含 API Key。
8. 在 `steps.md` 写明实际动作、可见结果、独立状态核对和所有异常。确认无异常后把 `- Acceptance result: PENDING` 改为 `- Acceptance result: PASS`，再运行 `scripts/acceptance/finish-run.sh <feature-slug>`。脚本检查八类证据、PNG/JSON 格式、测试和 build 成功标记、启动 bundle ID，并确认记录的 commit 与当前 checkout 完全一致。

## 失败与重跑

以下任一情况都判定失败：Xcode/Simulator 预检未通过；屏幕为空、被遮挡或显示旧版本；找不到稳定语义目标；操作未通过 Computer Use 完成；截图不是快捷键产生的完整桌面；测试、build 或 launch 失败；诊断 JSON 缺失、不可解析或与界面不一致；证据 commit 不匹配；需要系统权限、登录、上传或敏感数据输入但尚未获得用户明确许可。

失败时保留截图、日志、状态和失败步骤，把现有证据目录整体归档后修复，并从八步合同第 1 步重新执行。只清理由本次验收启动且明确属于 Interview Flashcard 的进程；不修改用户的系统设置、账户或其他 App。真实 DeepSeek smoke test 必须与确定性 stub 验收分开，并在输入或保存 API Key 前取得用户当次明确确认。

## Task 8：真实题目、真实 DeepSeek 与无限练习

Task 8 固定使用 Xcode beta 的 iPhone 17 Pro Max Simulator：

- `INTERVIEW_XCODE_DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer`
- `IF_SIMULATOR_UDID=779ACF98-BD23-4880-9F03-8DB9B9E43768`
- `IF_BUNDLE_ID=com.gaoguobin.InterviewFlashcard`
- 设备画面通过 Device Hub（`com.apple.dt.Devices`）读取；不要切换到其他 Simulator 或设备。

### 先做确定性检查

```bash
source ~/.zshrc
INTERVIEW_XCODE_DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer \
IF_SIMULATOR_UDID=779ACF98-BD23-4880-9F03-8DB9B9E43768 \
  scripts/dev/preflight.sh
xcodegen generate
bash scripts/acceptance/run-final-checks.sh
```

`run-final-checks.sh` 会重新生成工程，运行完整 XCTest 与 Debug build，使用 `real-question-demo`（随机种子 `20260805`）启动一次确定性 stub smoke，调用 `assert-iphone-app-metadata.sh`，扫描日志/诊断中的密钥和音频上传标记，并检查既有 Computer Use 证据以及 Task 8 证据。缺少最终截图、状态或视频时必须以 `BLOCKED` 退出，不能把静态通过写成验收通过。

### 真 AI 模式与缺 key 失败规则

真 AI 运行前，必须得到用户对本次 API key 使用的明确确认，并在已经 `source ~/.zshrc` 的 shell 中确认项目专用变量非空：

```bash
test -n "${INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY:-}" || {
  echo 'BLOCKED: INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY is required' >&2
  exit 1
}
```

启动真实路径时只允许使用 `--ai deepseek`，不得同时传 `--stub-mode` 或使用 `--ai stub`：

```bash
scripts/dev/build-and-launch.sh \
  --ai deepseek \
  --speech unsupported \
  --fixture real-question-demo \
  --random-seed 20260805
```

`build-and-launch.sh` 会在构建前检查 `INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY`，缺 key 必须明确 `BLOCKED` 并停止；AppRuntime 的 `.deepseek` 分支只创建 `DeepSeekAIClient`，不得回退到 Stub。启动日志只记录 `ai_provider=deepseek`、fixture、设备和请求计数，不得记录 key、Authorization header 或请求正文。若要证明缺 key 行为，可在隔离 shell 执行：

```bash
env -u INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY \
  scripts/dev/build-and-launch.sh --ai deepseek --speech unsupported
```

预期为非零退出并包含 `INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY is required`；不得出现 `ai_provider=stub` 的替代启动。

### 真实题目与界面检查点

`real-question-demo` 至少包含三道来自 `go-interview/question/` 的 Go 技术题：q022 的 `sync.Map.Load` 类型断言、q003 的 Unicode rune 字符串翻转、q015 的未初始化 channel/`time.Tick` 并发与泄漏边界。每道满分答案都必须有 `结论`、`核心要点`、`边界与取舍` 三个 Markdown 小节、至少三个不重复要点、机制、失败边界和工程权衡；Seeder 不创建任何假的回答、润色或评分记录。

按以下顺序操作并在每一步前重新读取 Device Hub 状态：

1. 从主屏幕点击 App Icon，确认竖屏、全屏、无黑边，冷启动直接出现一张彩色真实题卡；题池持续随机补充，单题池左滑后仍循环同一题。
2. 左滑当前题，确认仅跳过、不新增 AnswerAttempt，随后出现下一题；没有“本组完成”页面。
3. 打开过滤入口，确认全部主题默认选中、“包含已练习题”默认关闭；面板不包含题量选择或开始按钮。取消/应用后立即回到题卡。
4. 关闭面板后右滑进入回答；题卡正面和输入阶段都不显示满分答案。验证长题可以滚动且不被截断。
5. 输入带轻微输入法/语音转录噪声、但技术含义仍可辨的回答并提交。检查处理中只有一个评分请求、没有先行润色请求。
6. 结果首屏显示总分和 `evaluation.radar` 六维雷达图；向下滚动确认每个维度都有原回答中的具体引用、题目相关遗漏和可执行改进，满分答案仍显示三段资深结构和关键点。
7. 返回练习页确认回答后自动补卡；历史页确认原始回答、版本化满分答案、`keyPointsJSON`、六维分数和详情均已保存。

Task 8 证据统一写入 `diagnostics/acceptance/instant-practice-senior-evaluation/`：

`01-home-icon.png`、`02-cold-launch.png`、`03-filter-sheet.png`、`04-left-swipe.png`、`05-right-swipe-answer.png`、`06-long-question.png`、`07-import-quality-rejection.png`、`08-import-quality-success.png`、`09-evaluation-radar.png`、`10-evaluation-details.png`、`entry-state.json`、`computer-use-state.json`、`network-counts-redacted.log`、`demo-60s.mov`（视频不超过 60 秒）。截图必须由 Computer Use 快捷键触发并经收集脚本归档；状态从 App container 独立读取；网络日志只保留请求计数、operation、request ID 和 model ID，绝不保留 key 或回答原文。

如果真实 key 未获授权、网络不可用、Device Hub 无法显示 App 或任一证据缺失，保留失败日志并将 Task 8 标记为 `BLOCKED`；不得用 Stub 截图、假评分或手工生成的状态替代真实验收。可用 `scripts/acceptance/read-state.sh`、`xcrun simctl get_app_container "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" data` 和 `scripts/acceptance/finish-run.sh` 复核状态、证据格式及 commit 一致性。
