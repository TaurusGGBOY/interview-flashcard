#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"
readonly PROJECT_PATH="$REPOSITORY_ROOT/InterviewFlashcard.xcodeproj"
readonly DERIVED_DATA_PATH="$REPOSITORY_ROOT/.build/DerivedData"
readonly DEFAULT_LOG_PATH="$REPOSITORY_ROOT/.build/logs/tests.log"

usage() {
  echo "Usage: scripts/dev/test.sh [-only-testing:InterviewFlashcardTests/<SuiteName> ...]" >&2
  echo "Set IF_TEST_LOG_PATH to select the test log destination." >&2
  exit 2
}

blocked() {
  echo "BLOCKED: $*" >&2
  exit 1
}

for test_option in "$@"; do
  [[ "$test_option" == -only-testing:InterviewFlashcardTests/* ]] || usage
done

if [[ ! -r "$ACCEPTANCE_ENV_PATH" ]]; then
  blocked "run scripts/dev/preflight.sh successfully first; full Xcode and an iOS 26 Simulator are required"
fi
# shellcheck source=/dev/null
source "$ACCEPTANCE_ENV_PATH"
: "${INTERVIEW_XCODE_DEVELOPER_DIR:?missing INTERVIEW_XCODE_DEVELOPER_DIR}"
: "${IF_SIMULATOR_UDID:?missing IF_SIMULATOR_UDID}"

if [[ "$INTERVIEW_XCODE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
  blocked "Command Line Tools cannot build or test the iOS App"
fi
if [[ ! -x "$INTERVIEW_XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  blocked "full Xcode not found at $INTERVIEW_XCODE_DEVELOPER_DIR"
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  blocked "xcodegen is required; run scripts/dev/preflight.sh after installing it"
fi
if [[ ! -f "$REPOSITORY_ROOT/project.yml" ]]; then
  blocked "project.yml is missing from the current checkout"
fi

test_log_path="${IF_TEST_LOG_PATH:-$DEFAULT_LOG_PATH}"
if [[ "$test_log_path" != /* ]]; then
  test_log_path="$REPOSITORY_ROOT/$test_log_path"
fi
mkdir -p "$(dirname "$test_log_path")" "$DERIVED_DATA_PATH"

echo "Generating Xcode project from $REPOSITORY_ROOT/project.yml"
(
  cd "$REPOSITORY_ROOT"
  xcodegen generate
)

if [[ ! -d "$PROJECT_PATH" ]]; then
  blocked "XcodeGen did not create $PROJECT_PATH"
fi

echo "Testing commit: $(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
echo "Destination: platform=iOS Simulator,id=$IF_SIMULATOR_UDID"
echo "Log: $test_log_path"

DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" \
  "$INTERVIEW_XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" \
  -project "$PROJECT_PATH" \
  -scheme InterviewFlashcard \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$IF_SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test \
  "$@" \
  2>&1 | tee "$test_log_path"
