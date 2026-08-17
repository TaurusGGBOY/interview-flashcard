#!/usr/bin/env bash
set -u

PROJECT_ROOT="${PROJECT_ROOT:-$(cd -- "$(dirname -- "$0")/../.." && pwd -P)}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/gaoguobin/Downloads/Xcode-beta.app/Contents/Developer}"
TARGET_UDID="${TARGET_UDID:-00008150-00096D3C3621401C}"
BUNDLE_ID="${BUNDLE_ID:-com.gaoguobin.InterviewFlashcard}"
CC_SWITCH_DB_PATH="${CC_SWITCH_DB_PATH:-/Users/gaoguobin/.cc-switch/cc-switch.db}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
RETRY_INTERVAL="${RETRY_INTERVAL:-15}"
LOG_FILE="${LOG_FILE:-$PROJECT_ROOT/diagnostics/acceptance/physical-install/keep-awake-monitor.log}"

mkdir -p "$(dirname -- "$LOG_FILE")"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

device_is_connected() {
  local device_json
  device_json="$(
    env DEVELOPER_DIR="$DEVELOPER_DIR" xcrun devicectl list devices \
      --json-output - 2>/dev/null
  )" || return 1

  python3 -c '
import json
import sys

try:
    document = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

target_udid = sys.argv[1]
for device in document.get("result", {}).get("devices", []):
    properties = device.get("properties", {})
    hardware = properties.get("hardware", {})
    connection = properties.get("connection", {})
    if (
        hardware.get("udid") == target_udid
        and hardware.get("reality") == "physical"
        and connection.get("state") == "connected"
        and connection.get("transportType") == "wired"
    ):
        raise SystemExit(0)
raise SystemExit(1)
' "$TARGET_UDID" <<< "$device_json"
}

read_cc_switch_config() {
  python3 - "$CC_SWITCH_DB_PATH" <<'PY'
import json
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as database:
    row = database.execute(
        """
        SELECT settings_config, meta
        FROM providers
        WHERE app_type = 'claude' AND is_current = 1
        LIMIT 1
        """
    ).fetchone()

if row is None:
    raise SystemExit("no current cc-switch Claude provider")

settings = json.loads(row[0])
environment = settings.get("env", {})
api_key = environment.get("ANTHROPIC_AUTH_TOKEN", "").strip()
model = (
    environment.get("ANTHROPIC_MODEL")
    or environment.get("ANTHROPIC_DEFAULT_SONNET_MODEL")
    or settings.get("model")
    or ""
).strip()
if not api_key or not model:
    raise SystemExit("current cc-switch Claude provider is incomplete")

# cc-switch is used only as a key store here. Its Claude Code relay
# (ANTHROPIC_BASE_URL) is Mac-only and speaks Anthropic Messages, which the
# app must not use. The physical app always talks directly to the OpenCode Go
# subscription endpoint over the OpenAI Responses protocol.
base_url = "https://opencode.ai/zen/go"
provider = "openai"

# The key is emitted only into the parent shell's private variables. It is
# never written to the monitor log or supplied as a command-line argument.
print("\t".join((base_url, api_key, model, provider)))
PY
}

launch_keep_awake_app() {
  local config base_url api_key model provider launch_output
  config="$(read_cc_switch_config 2>/dev/null)" || {
    log "connected, but cc-switch configuration was unavailable"
    return 1
  }
  IFS=$'\t' read -r base_url api_key model provider <<< "$config"

  if [[ "$base_url" != "https://opencode.ai/zen/go" || "$provider" != "openai" ]]; then
    log "connected, but refusing non-OpenCode-Go provider configuration"
    return 1
  fi

  launch_output="$(
    DEVICECTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_API_KEY="$api_key" \
    DEVICECTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_BASE_URL="$base_url" \
    DEVICECTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_MODEL="$model" \
    DEVICECTL_CHILD_INTERVIEW_FLASHCARD_DEEPSEEK_PROVIDER="$provider" \
    env DEVELOPER_DIR="$DEVELOPER_DIR" xcrun devicectl device process launch \
      --terminate-existing \
      --device "$TARGET_UDID" \
      "$BUNDLE_ID" \
      -- \
      -IFDiagnosticsEnabled YES \
      -IFAIProvider deepseek \
      -IFKeepAwake YES 2>&1
  )" || {
    if [[ "$launch_output" == *"BSErrorCodeDescription = Locked"* ||
          "$launch_output" == *"device was not, or could not, be unlocked"* ]]; then
      log "connected, but iPhone is locked; waiting for iOS to allow the automatic launch"
      return 1
    fi
    log "keep-awake launch failed: ${launch_output//$'\n'/ }"
    return 1
  }

  log "connected; keep-awake mode enabled for $BUNDLE_ID"
  return 0
}

log "monitor started for physical iPhone UDID $TARGET_UDID"
was_connected=0
launch_succeeded=0
next_retry=0

while true; do
  now="$(date '+%s')"
  if device_is_connected; then
    if (( ! was_connected )); then
      log "target iPhone connected"
      launch_succeeded=0
      next_retry=0
    fi

    if (( ! launch_succeeded && now >= next_retry )); then
      if launch_keep_awake_app; then
        launch_succeeded=1
      else
        next_retry=$((now + RETRY_INTERVAL))
      fi
    fi
    was_connected=1
  else
    if (( was_connected )); then
      log "target iPhone disconnected; normal app idle behavior restored"
    fi
    was_connected=0
    launch_succeeded=0
    next_retry=0
  fi
  sleep "$POLL_INTERVAL"
done
