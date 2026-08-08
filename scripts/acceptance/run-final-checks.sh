#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"
readonly PROJECT_PATH="$REPOSITORY_ROOT/InterviewFlashcard.xcodeproj"
readonly DERIVED_DATA_PATH="$REPOSITORY_ROOT/.build/DerivedData"
readonly APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app"
readonly PINNED_SIMULATOR_UDID="779ACF98-BD23-4880-9F03-8DB9B9E43768"
readonly PINNED_SIMULATOR_NAME="iPhone 17 Pro Max"
readonly BETA_DEVELOPER_DIR="/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer"

echo "== InterviewFlashcard final checks =="

if [[ -r "$ACCEPTANCE_ENV_PATH" ]]; then
  # shellcheck source=/dev/null
  source "$ACCEPTANCE_ENV_PATH"
fi

if ! "$REPOSITORY_ROOT/scripts/dev/preflight.sh"; then
  echo "BLOCKED: full Xcode/iOS Simulator preflight did not pass; static checks continue." >&2
  static_only="true"
else
  static_only="false"
  if [[ -r "$ACCEPTANCE_ENV_PATH" ]]; then
    # preflight rewrites this file after resolving the installed runtime/device;
    # validate the exact values used by the subsequent build against that file.
    # shellcheck source=/dev/null
    source "$ACCEPTANCE_ENV_PATH"
  fi
fi

if [[ "$static_only" == "false" ]]; then
  : "${INTERVIEW_XCODE_DEVELOPER_DIR:?preflight did not provide a developer directory}"
  : "${IF_SIMULATOR_UDID:?preflight did not provide a Simulator UDID}"
  [[ "$INTERVIEW_XCODE_DEVELOPER_DIR" == "$BETA_DEVELOPER_DIR" ]] || {
    echo "FAILED: final checks must use Xcode beta at $BETA_DEVELOPER_DIR" >&2
    exit 1
  }
  [[ "$IF_SIMULATOR_UDID" == "$PINNED_SIMULATOR_UDID" ]] || {
    echo "FAILED: final checks must use $PINNED_SIMULATOR_NAME ($PINNED_SIMULATOR_UDID)" >&2
    exit 1
  }
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "FAILED: xcodegen is required for final checks" >&2
  exit 1
fi
xcodegen generate >/dev/null
[[ -d "$PROJECT_PATH" ]] || {
  echo "FAILED: xcodegen did not create $PROJECT_PATH" >&2
  exit 1
}

bash -n "$REPOSITORY_ROOT/scripts/dev/preflight.sh" \
  "$REPOSITORY_ROOT/scripts/dev/test.sh" \
  "$REPOSITORY_ROOT/scripts/dev/build-and-launch.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/start-run.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/collect-screenshot.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/read-state.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/finish-run.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/assert-iphone-app-metadata.sh"

while IFS= read -r -d '' swift_file; do
  swiftc -frontend -parse "$swift_file" >/dev/null
done < <(find "$REPOSITORY_ROOT/InterviewFlashcard" "$REPOSITORY_ROOT/InterviewFlashcardTests" -type f -name '*.swift' -print0)

if [[ "$static_only" == "false" ]]; then
  mkdir -p "$REPOSITORY_ROOT/.build/logs" "$DERIVED_DATA_PATH"
  DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" \
    "$INTERVIEW_XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT_PATH" \
    -scheme InterviewFlashcard \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$IF_SIMULATOR_UDID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    test 2>&1 | tee "$REPOSITORY_ROOT/.build/logs/final-tests.log"

  DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" \
    "$INTERVIEW_XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT_PATH" \
    -scheme InterviewFlashcard \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$IF_SIMULATOR_UDID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build 2>&1 | tee "$REPOSITORY_ROOT/.build/logs/final-build.log"
  "$REPOSITORY_ROOT/scripts/acceptance/assert-iphone-app-metadata.sh" "$APP_PATH"

  IF_BUILD_LOG_PATH="$REPOSITORY_ROOT/.build/logs/final-build.log" \
    IF_LAUNCH_LOG_PATH="$REPOSITORY_ROOT/.build/logs/final-launch.log" \
    "$REPOSITORY_ROOT/scripts/dev/build-and-launch.sh" \
      --ai stub --stub-mode success --speech unsupported --fixture mvp-workflow
fi

# A requested live run must fail before building or launching when the project
# key is absent; it must never silently fall back to the deterministic stub.
missing_key_output="$(env -u INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY \
  "$REPOSITORY_ROOT/scripts/dev/build-and-launch.sh" \
    --ai deepseek --speech unsupported 2>&1 || true)"
if [[ "$missing_key_output" != *"INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY is required"* ]]; then
  echo "FAILED: --ai deepseek without a key did not fail explicitly" >&2
  exit 1
fi

privacy_pattern='Authorization:[[:space:]]*Bearer|secret-marker|https?://[^[:space:]]*\.m4a|audio(_|-)url'
while IFS= read -r -d '' path; do
  if rg -n -i "$privacy_pattern" "$path"; then
    echo "FAILED: sensitive token or audio upload marker found in $path" >&2
    exit 1
  fi
done < <(
  find "$REPOSITORY_ROOT/.build/logs" "$REPOSITORY_ROOT/diagnostics" \
    "$REPOSITORY_ROOT/build.log" "$REPOSITORY_ROOT/launch.log" \
    -type f -print0 2>/dev/null || true
)

if git -C "$REPOSITORY_ROOT" status --short --untracked-files=all | rg -n '(^|[[:space:]])InterviewFlashcard\.xcodeproj/' ; then
  echo "FAILED: generated Xcode project contains unignored files" >&2
  exit 1
fi

required_features=(
  iphone17-fullscreen
  practice-swipe
  practice-session-layout
  practice-undo-accessibility
  practice-session-complete
  answer-composer-iphone17
  answer-result-success
  answer-result-failure
)
required_evidence=(context.txt tests.log build.log launch.log steps.md before.png after.png state.json)
missing_evidence=0
for feature in "${required_features[@]}"; do
  feature_dir="$REPOSITORY_ROOT/diagnostics/mac-ui/$feature"
  for evidence_name in "${required_evidence[@]}"; do
    if [[ ! -s "$feature_dir/$evidence_name" ]]; then
      echo "BLOCKED: missing Computer Use evidence $feature/$evidence_name" >&2
      missing_evidence=1
    fi
  done
done

acceptance_dir="$REPOSITORY_ROOT/diagnostics/acceptance/instant-practice-senior-evaluation"
acceptance_evidence=(
  01-home-icon.png
  02-cold-launch.png
  03-filter-sheet.png
  04-left-swipe.png
  05-right-swipe-answer.png
  06-long-question.png
  07-import-quality-rejection.png
  08-import-quality-success.png
  09-evaluation-radar.png
  10-evaluation-details.png
  entry-state.json
  computer-use-state.json
  network-counts-redacted.log
  demo-60s.mov
)
for evidence_name in "${acceptance_evidence[@]}"; do
  if [[ ! -s "$acceptance_dir/$evidence_name" ]]; then
    echo "BLOCKED: missing live acceptance evidence $acceptance_dir/$evidence_name" >&2
    missing_evidence=1
  fi
done
if [[ "$missing_evidence" -ne 0 ]]; then
  echo "BLOCKED: deterministic build checks passed, but Computer Use evidence is incomplete" >&2
  exit 2
fi

echo "PASS: static source/script checks completed"
if [[ "$static_only" == "true" ]]; then
  echo "NOTE: build/test/Computer Use remain blocked until full Xcode and an iOS Simulator are installed."
fi
