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
    echo "  --ai <deepseek|cc-switch>"
    echo "  --acceptance-import-file <host-path>"
    echo "  --acceptance-continue-run-id <uuid>"
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

ai_provider="cc-switch"
requested_ai_provider="cc-switch"
acceptance_import_file=""
acceptance_continue_run_id=""
fixture_name=""
random_seed=""
keep_data="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ai)
      require_value "$1" "$#"
      ai_provider="$2"
      requested_ai_provider="$2"
      shift 2
      ;;
    --acceptance-import-file)
      require_value "$1" "$#"
      acceptance_import_file="$2"
      shift 2
      ;;
    --acceptance-continue-run-id)
      require_value "$1" "$#"
      acceptance_continue_run_id="$2"
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

[[ "$ai_provider" == "deepseek" || "$ai_provider" == "cc-switch" ]] || {
  if [[ "$ai_provider" == "stub" ]]; then
    blocked "Simulator launches must use the real DeepSeek provider; --ai stub is disabled"
  fi
  echo "Invalid --ai value: $ai_provider" >&2
  usage
}
if [[ -n "$fixture_name" && ! "$fixture_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
  echo "Invalid --fixture value: $fixture_name" >&2
  usage
fi
if [[ -n "$acceptance_import_file" ]]; then
  [[ -r "$acceptance_import_file" ]] || blocked "acceptance import file is not readable: $acceptance_import_file"
  [[ "$acceptance_import_file" == *.md ]] || blocked "acceptance import file must be Markdown: $acceptance_import_file"
  [[ -z "$fixture_name" ]] || blocked "live Markdown import cannot be combined with a fixture"
fi
if [[ -n "$acceptance_continue_run_id" && ! "$acceptance_continue_run_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "Invalid --acceptance-continue-run-id value: $acceptance_continue_run_id" >&2
  usage
fi
if [[ -n "$acceptance_import_file" && -n "$acceptance_continue_run_id" ]]; then
  blocked "a live Markdown import cannot continue an existing run in the same launch"
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

if [[ "$requested_ai_provider" == "cc-switch" ]]; then
  cc_switch_db_path="${CC_SWITCH_DB_PATH:-${HOME}/.cc-switch/cc-switch.db}"
  [[ -r "$cc_switch_db_path" ]] || blocked "cc-switch database is not readable: $cc_switch_db_path"

  cc_switch_values="$(python3 - "$cc_switch_db_path" <<'PY'
import json
import os
import sqlite3
import sys

database_path = sys.argv[1]
connection = sqlite3.connect(database_path)
row = connection.execute(
    """
        SELECT settings_config, meta
    FROM providers
    WHERE app_type = "claude" AND is_current = 1
    LIMIT 1
    """
).fetchone()
if row is None:
    raise SystemExit("cc-switch has no current Claude provider")

settings = json.loads(row[0])
meta = json.loads(row[1] or "{}")
environment = settings.get("env", {})
base_url = environment.get("ANTHROPIC_BASE_URL", "").strip().rstrip("/")
api_key = environment.get("ANTHROPIC_AUTH_TOKEN", "").strip()
model = (
    environment.get("ANTHROPIC_MODEL")
    or environment.get("ANTHROPIC_DEFAULT_SONNET_MODEL")
    or settings.get("model")
    or ""
).strip()
api_format = str(meta.get("apiFormat") or "openai-compatible").strip().lower()
provider = {
    "anthropic": "anthropic",
    "openai": "openai",
    "openai-compatible": "openai-compatible",
    "openai_compatible": "openai-compatible",
}.get(api_format)
if provider is None:
    raise SystemExit("current cc-switch provider has an unsupported API format: " + api_format)
if not base_url or not api_key or not model:
    raise SystemExit("current cc-switch provider lacks base URL, key, or model")

# cc-switch stores the provider root for the active provider.
# OpenAI adapters use the provider /v1 prefix before their endpoint path.
if provider == "anthropic" and base_url.lower().startswith(("http://127.0.0.1", "http://localhost", "https://127.0.0.1", "https://localhost")):
    proxy_config_path = os.environ.get(
        "CC_SWITCH_PROXY_CONFIG_PATH",
        os.path.expanduser("~/.claude/search-proxy/config.json"),
    )
    try:
        with open(proxy_config_path, encoding="utf-8") as config_file:
            proxy_config = json.load(config_file)
        upstream = proxy_config["upstream"]
        upstream_host = str(upstream["hostname"]).strip()
        upstream_path = str(upstream["path"]).strip().rstrip("/")
        endpoint_suffix = "/v1/messages"
        if not upstream_host or not upstream_path.endswith(endpoint_suffix):
            raise ValueError("upstream is not an Anthropic Messages endpoint")
        base_url = "https://" + upstream_host + upstream_path[:-len(endpoint_suffix)].rstrip("/")
        upstream_key = str(upstream.get("apiKey", "")).strip()
        if upstream_key:
            api_key = upstream_key
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(
            "current cc-switch provider uses a local relay, but its direct "
            "OpenCode Go configuration could not be read: " + str(error)
        )
elif provider != "anthropic" and not base_url.endswith("/v1"):
    base_url += "/v1"
print("\t".join((base_url, api_key, model, provider)))
PY
  )" || blocked "unable to read the active cc-switch provider"
  IFS=$'\t' read -r INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL \
    INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY \
    INTERVIEW_FLASHCARD_DEEPSEEK_MODEL \
    INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER <<< "$cc_switch_values"
  [[ -n "$INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL" && \
     -n "$INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY" && \
     -n "$INTERVIEW_FLASHCARD_DEEPSEEK_MODEL" ]] || blocked "unable to read the active cc-switch provider"
  [[ "$INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL" == "https://opencode.ai/zen/go" && \
     "$INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER" == "anthropic" ]] || \
    blocked "cc-switch must resolve to the OpenCode Go endpoint for this app"
  export INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL
  export INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY
  export INTERVIEW_FLASHCARD_DEEPSEEK_MODEL
  export INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER
  ai_provider="deepseek"
fi

if [[ "$ai_provider" == "deepseek" && -z "${INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY:-}" ]]; then
  blocked "INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY is required for --ai $requested_ai_provider; source ~/.zshrc first"
fi

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

"$REPOSITORY_ROOT/scripts/acceptance/assert-iphone-app-metadata.sh" "$APP_PATH"

launch_arguments=(
  -IFDiagnosticsEnabled YES
  -IFAIProvider "$ai_provider"
)
if [[ -n "$fixture_name" ]]; then
  launch_arguments+=( -IFSeedFixture "$fixture_name" )
fi
if [[ -n "$random_seed" ]]; then
  launch_arguments+=( -IFRandomSeed "$random_seed" )
fi
if [[ -n "$acceptance_import_file" ]]; then
  launch_arguments+=( -IFAcceptanceImportFile "Acceptance/source.md" )
fi
if [[ -n "$acceptance_continue_run_id" ]]; then
  launch_arguments+=( -IFAcceptanceContinueRunID "$acceptance_continue_run_id" )
fi

echo "Launch log: $launch_log_path"
{
  echo "commit=$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
  echo "bundle_id=$IF_BUNDLE_ID"
  echo "simulator_udid=$IF_SIMULATOR_UDID"
  echo "ai_provider=$requested_ai_provider"
  echo "deepseek_model=${INTERVIEW_FLASHCARD_DEEPSEEK_MODEL:-configured-in-app}"
  echo "deepseek_base_url=${INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL:-configured-in-app}"
  echo "acceptance_import_file=$(basename "${acceptance_import_file:-none}")"
  echo "acceptance_continue_run_id=${acceptance_continue_run_id:-none}"
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
  if [[ -n "$acceptance_import_file" ]]; then
    app_data_container="$(DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl get_app_container "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" data)"
    acceptance_destination="$app_data_container/Documents/Acceptance/source.md"
    mkdir -p "$(dirname "$acceptance_destination")"
    cp "$acceptance_import_file" "$acceptance_destination"
    echo "Copied real Markdown into the Simulator app container"
  fi
  SIMCTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY="$INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY" \
  SIMCTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL="${INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL:-}" \
  SIMCTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_MODEL="${INTERVIEW_FLASHCARD_DEEPSEEK_MODEL:-}" \
  SIMCTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER="${INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER:-}" \
    DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl launch "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" "${launch_arguments[@]}"
} 2>&1 | tee "$launch_log_path"
