#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"

usage() {
  echo "Usage: scripts/acceptance/read-state.sh <feature-slug>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
readonly FEATURE_SLUG="$1"
[[ "$FEATURE_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || usage

if [[ ! -r "$ACCEPTANCE_ENV_PATH" ]]; then
  echo "BLOCKED: run scripts/dev/preflight.sh successfully first" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ACCEPTANCE_ENV_PATH"
: "${INTERVIEW_XCODE_DEVELOPER_DIR:?missing INTERVIEW_XCODE_DEVELOPER_DIR}"
: "${IF_SIMULATOR_UDID:?missing IF_SIMULATOR_UDID}"
: "${IF_BUNDLE_ID:?missing IF_BUNDLE_ID}"

readonly RUN_DIR="$REPOSITORY_ROOT/diagnostics/mac-ui/$FEATURE_SLUG"
readonly DESTINATION_PATH="$RUN_DIR/state.json"
if [[ ! -f "$RUN_DIR/context.txt" ]]; then
  echo "BLOCKED: start the acceptance run first" >&2
  exit 1
fi
if [[ -e "$DESTINATION_PATH" ]]; then
  echo "BLOCKED: $DESTINATION_PATH already exists; refusing to replace evidence" >&2
  exit 1
fi

app_container="$(DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" xcrun simctl get_app_container "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" data)" || {
  echo "BLOCKED: the current App is not installed in the selected Simulator" >&2
  exit 1
}
readonly SOURCE_PATH="$app_container/Library/Application Support/Diagnostics/state.json"

if [[ ! -s "$SOURCE_PATH" ]]; then
  echo "BLOCKED: diagnostic state is missing or empty: $SOURCE_PATH" >&2
  exit 1
fi
if ! plutil -lint "$SOURCE_PATH" >/dev/null; then
  echo "BLOCKED: diagnostic state is not valid JSON" >&2
  exit 1
fi

temporary_destination="$(mktemp "$RUN_DIR/state.json.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_destination:-}" && -f "$temporary_destination" ]]; then
    rm -f "$temporary_destination"
  fi
}
trap cleanup EXIT

cp "$SOURCE_PATH" "$temporary_destination"
mv "$temporary_destination" "$DESTINATION_PATH"
temporary_destination=""

echo "Read diagnostic state: $DESTINATION_PATH"
plutil -p "$DESTINATION_PATH"
