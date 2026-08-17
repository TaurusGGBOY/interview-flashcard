

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

## Vision Analysis Bridge (mandatory rule)

When the current model does NOT support image/vision input (e.g. DeepSeek V4 Flash), and the task requires true visual understanding of a screenshot, screen capture, or image (via computer-use, browser screenshots, or any image file):

1. Follow the `vision-computer-use` skill instructions (located at `~/.codex/skills/vision-computer-use/SKILL.md`).
2. Capture or locate the image to analyze (e.g. computer-use screenshot, saved to a local path).
3. Spawn a sub-agent with `model: "gpt-5.6-luna"` to inspect the image with `view_image` and describe what it visually sees.
4. Wait for the sub-agent result, use its visual description in reasoning, then close the sub-agent.

Do NOT attempt to analyze images directly when the active model does not support vision. Prefer accessibility/DOM text for cheap reads; use the vision bridge only when rendered appearance truly matters.
