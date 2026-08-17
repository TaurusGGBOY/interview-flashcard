

## Migration History
- 2026-08-08: Project migrated from `/Users/gaoguobin/project/interview-flashcard` to `/Volumes/my_disk/project/interview-flashcard`.
- Canonical project path: `/Volumes/my_disk/project/interview-flashcard`.
- Keep agent instructions in `AGENTS.md`; `CLAUDE.md` is a symlink to it.

## Xcode Environment
- Xcode Beta is installed at `/Users/gaoguobin/Downloads/Xcode-beta.app`, not under `/Applications`.
- The default `xcode-select` path may point to `/Library/Developer/CommandLineTools`, which makes `xcodebuild` and `simctl` appear unavailable.
- For project builds and iOS Simulator tests, use:
  `DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer`
- Verified on 2026-08-17: Xcode `27.0` (build `27A5228h`) with iOS `27.0` Simulator runtimes.

## Physical iPhone background testing

- Target device: `wode的iPhone`, UDID `8D55ABDB-E037-50BB-B9D7-6AAE513BE451`.
- Use `DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer` for every device command.
- `devicectl` install/launch/capture is reliable from the shell. The physical installer is:
  `.agents/skills/install-interviewflashcard-iphone/scripts/open-unlock-terminal.sh`.
- Do not treat plain agent-shell `nohup xcodebuild test` as the physical-test workflow for this project. It was observed to exit during package/test preparation without reaching test execution, and unsigned/background test runners can fail with `0xe8008018` or lose the IDE connection.
- For a background test job, start `xcodebuild` from a visible Terminal GUI context so `codesign` can access the login keychain, then let the command continue in that Terminal session and poll its log/result bundle from the agent shell. Use this pattern (never put passwords or API keys in the command):

  ```bash
  osascript -e 'tell application "Terminal" to do script "cd /Volumes/my_disk/project/interview-flashcard && DEVELOPER_DIR=/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer xcodebuild test -project InterviewFlashcard.xcodeproj -scheme InterviewFlashcard -destination '\''platform=iOS,id=8D55ABDB-E037-50BB-B9D7-6AAE513BE451'\'' -derivedDataPath .build/PhysicalTest -resultBundlePath .build/PhysicalTest/result.xcresult DEVELOPMENT_TEAM=6VX3B4X4XR -allowProvisioningUpdates > /tmp/codextmp/physical-ui-test.log 2>&1; echo $? > /tmp/codextmp/physical-ui-test.exit"'
  ```

- Poll `/tmp/codextmp/physical-ui-test.log` and inspect `.build/PhysicalTest/result.xcresult`. A successful build/install/launch is not a passing UI test; use Device Hub Computer Use for the final visual interaction and result-page verification.
- The visible installer Terminal must not be closed manually while it is running. The helper now waits for an explicit completion marker written after the installer and all `devicectl` children exit, then closes only its own Terminal window. If macOS shows “closing this window will terminate bash/devicectl,” the command is still running; wait for the helper's `Physical-device installer finished` message.
- OpenCode Go's `mimo-v2.5` uses `https://opencode.ai/zen/go/v1/chat/completions`; do not configure this model through `/v1/responses`.

## Vision Analysis Bridge (mandatory rule)

When the current model does NOT support image/vision input (e.g. DeepSeek V4 Flash), and the task requires true visual understanding of a screenshot, screen capture, or image (via computer-use, browser screenshots, or any image file):

1. Follow the `vision-computer-use` skill instructions (located at `~/.codex/skills/vision-computer-use/SKILL.md`).
2. Capture or locate the image to analyze (e.g. computer-use screenshot, saved to a local path).
3. Spawn a sub-agent with `model: "gpt-5.6-luna"` to inspect the image with `view_image` and describe what it visually sees.
4. Wait for the sub-agent result, use its visual description in reasoning, then close the sub-agent.

Do NOT attempt to analyze images directly when the active model does not support vision. Prefer accessibility/DOM text for cheap reads; use the vision bridge only when rendered appearance truly matters.
