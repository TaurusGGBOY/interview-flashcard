# InterviewFlashcard MVP Sign-off

## Current gate

The repository has deterministic fixtures, unit-test targets, build/launch scripts, and a Computer Use runbook. Full build and Simulator acceptance are **blocked** until `/Applications/Xcode.app` and an iOS 26 Simulator runtime are available on this Mac. Command Line Tools alone cannot compile SwiftData macros or drive an iOS Simulator.

## Deterministic acceptance matrix

| Area | Fixture / mode | Evidence directory | Status |
|---|---|---|---|
| App shell and persistence | `empty` | `diagnostics/mac-ui/app-shell/` | pending Xcode |
| Markdown import and 50-item batches | `long-interview.md` | `diagnostics/mac-ui/markdown-import/` | pending Xcode |
| Pure random draw and practiced toggle | `practice-mixed` | `diagnostics/mac-ui/practice-random/` | pending Xcode |
| Text polish/evaluation | `processing`, `success` | `diagnostics/mac-ui/text-answer/` | pending Xcode |
| Local speech capability gate | `--speech unsupported` / `fixture-supported` | `diagnostics/mac-ui/voice-answer/` | pending Xcode |
| History and per-question timeline | `history` | `diagnostics/mac-ui/answer-history/` | pending Xcode |
| Review statistics | `insights` | `diagnostics/mac-ui/review-statistics/` | pending Xcode |
| Trash, restore, permanent-delete warning | `trash` | `diagnostics/mac-ui/trash-restore/` | pending Xcode |

Each completed run must be created with `scripts/acceptance/start-run.sh`, exercised through macOS Computer Use, and closed with `scripts/acceptance/finish-run.sh`. No screenshot or state file is treated as evidence until the app was actually built and launched on the current commit.

## Real-provider and physical-device gates

The DeepSeek smoke test requires explicit user confirmation immediately before saving a real API key. The key must be entered through Settings, cleared afterward, and never appear in diagnostics or logs. Physical-iPhone offline speech remains a separate gate; Simulator fixture speech does not prove on-device recognition.
