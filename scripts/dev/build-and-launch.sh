#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"
readonly PROJECT_PATH="$REPOSITORY_ROOT/InterviewFlashcard.xcodeproj"
readonly DERIVED_DATA_PATH="$REPOSITORY_ROOT/.build/DerivedData"
readonly APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/InterviewFlashcard.app"
readonly DEFAULT_BUILD_LOG_PATH="$REPOSITORY_ROOT/.build/logs/build.log"
readonly DEFAULT_LAUNCH_LOG_PATH="$REPOSITORY_ROOT/.build/logs/launch.log"

usage() {
  {
    echo "Usage: scripts/dev/build-and-launch.sh [options]"
    echo
    echo "Options:"
    echo "  --ai <stub|deepseek>"
    echo "  --stub-mode <mode>"
    echo "  --speech <capability>"
    echo "  --fixture <name>"
    echo "  --random-seed <non-negative-integer>"
    echo "  --keep-data"
    echo
    echo "Set IF_BUILD_LOG_PATH and IF_LAUNCH_LOG_PATH to select log destinations."
  } >&2
  exit 2
}

blocked() {
  echo "BLOCKED: $*" >&2
  exit 1
}

require_value() {
  local option_name="$1"
  local value_count="$2"
  if [[ "$value_count" -lt 2 ]]; then
    echo "Missing value for $option_name" >&2
    usage
  fi
}

ai_provider="stub"
stub_mode="success"
speech_capability="unsupported"
fixture_name=""
random_seed=""
keep_data="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ai)
      require_value "$1" "$#"
      ai_provider="$2"
      shift 2
      ;;
    --stub-mode)
      require_value "$1" "$#"
      stub_mode="$2"
      shift 2
      ;;
    --speech)
      require_value "$1" "$#"
      speech_capability="$2"
      shift 2
      ;;
    --fixture)
      require_value "$1" "$#"
      fixture_name="$2"
      shift 2
      ;;
    --random-seed)
      require_value "$1" "$#"
      random_seed="$2"
      shift 2
      ;;
    --keep-data)
      keep_data="true"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

[[ "$ai_provider" == "stub" || "$ai_provider" == "deepseek" ]] || {
  echo "Invalid --ai value: $ai_provider" >&2
  usage
}
[[ "$stub_mode" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
  echo "Invalid --stub-mode value: $stub_mode" >&2
  usage
}
[[ "$speech_capability" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
  echo "Invalid --speech value: $speech_capability" >&2
  usage
}
if [[ -n "$fixture_name" && ! "$fixture_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
  echo "Invalid --fixture value: $fixture_name" >&2
  usage
fi
if [[ -n "$random_seed" && ! "$random_seed" =~ ^[0-9]+$ ]]; then
  echo "Invalid --random-seed value: $random_seed" >&2
  usage
fi

if [[ ! -r "$ACCEPTANCE_ENV_PATH" ]]; then
  blocked "run scripts/dev/preflight.sh successfully first; full Xcode and an iOS 26 Simulator are required"
fi
# shellcheck source=/dev/null
source "$ACCEPTANCE_ENV_PATH"
: "${INTERVIEW_XCODE_DEVELOPER_DIR:?missing INTERVIEW_XCODE_DEVELOPER_DIR}"
: "${IF_SIMULATOR_UDID:?missing IF_SIMULATOR_UDID}"
: "${IF_BUNDLE_ID:?missing IF_BUNDLE_ID}"

if [[ "$INTERVIEW_XCODE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
  blocked "Command Line Tools cannot build or launch the iOS App"
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

build_log_path="${IF_BUILD_LOG_PATH:-$DEFAULT_BUILD_LOG_PATH}"
launch_log_path="${IF_LAUNCH_LOG_PATH:-$DEFAULT_LAUNCH_LOG_PATH}"
if [[ "$build_log_path" != /* ]]; then
  build_log_path="$REPOSITORY_ROOT/$build_log_path"
fi
if [[ "$launch_log_path" != /* ]]; then
  launch_log_path="$REPOSITORY_ROOT/$launch_log_path"
fi
if [[ "$build_log_path" == "$launch_log_path" ]]; then
  blocked "build and launch logs must use different paths"
fi
mkdir -p "$(dirname "$build_log_path")" "$(dirname "$launch_log_path")" "$DERIVED_DATA_PATH"

echo "Generating Xcode project from $REPOSITORY_ROOT/project.yml"
(
  cd "$REPOSITORY_ROOT"
  xcodegen generate
)

if [[ ! -d "$PROJECT_PATH" ]]; then
  blocked "XcodeGen did not create $PROJECT_PATH"
fi

echo "Building commit: $(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
echo "Destination: platform=iOS Simulator,id=$IF_SIMULATOR_UDID"
echo "Build log: $build_log_path"

DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" \
  "$INTERVIEW_XCODE_DEVELOPER_DIR/usr/bin/xcodebuild" \
  -project "$PROJECT_PATH" \
  -scheme InterviewFlashcard \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$IF_SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  2>&1 | tee "$build_log_path"

if [[ ! -d "$APP_PATH" ]]; then
  blocked "build succeeded but App product is missing: $APP_PATH"
fi

launch_arguments=(
  -IFDiagnosticsEnabled YES
  -IFAIProvider "$ai_provider"
  -IFStubMode "$stub_mode"
  -IFSpeechCapability "$speech_capability"
)
if [[ -n "$fixture_name" ]]; then
  launch_arguments+=( -IFSeedFixture "$fixture_name" )
fi
if [[ -n "$random_seed" ]]; then
  launch_arguments+=( -IFRandomSeed "$random_seed" )
fi

echo "Launch log: $launch_log_path"
{
  echo "commit=$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
  echo "bundle_id=$IF_BUNDLE_ID"
  echo "simulator_udid=$IF_SIMULATOR_UDID"
  echo "ai_provider=$ai_provider"
  echo "stub_mode=$stub_mode"
  echo "speech_capability=$speech_capability"
  echo "fixture=${fixture_name:-none}"
  echo "random_seed=${random_seed:-none}"
  echo "keep_data=$keep_data"

  DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl bootstatus "$IF_SIMULATOR_UDID" -b

  if DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl get_app_container "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" app >/dev/null 2>&1; then
    DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl terminate "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" >/dev/null 2>&1 || true
    echo "Terminated existing $IF_BUNDLE_ID process if it was running"
    if [[ "$keep_data" == "false" ]]; then
      DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl uninstall "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID"
      echo "Uninstalled existing $IF_BUNDLE_ID data container"
    fi
  else
    echo "No existing $IF_BUNDLE_ID installation found"
  fi

  DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl install "$IF_SIMULATOR_UDID" "$APP_PATH"
  echo "Installed current App product: $APP_PATH"
  DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl launch "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" "${launch_arguments[@]}"
} 2>&1 | tee "$launch_log_path"
