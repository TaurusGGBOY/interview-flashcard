#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  echo "Usage: scripts/acceptance/collect-screenshot.sh <feature-slug> <before|after>" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
readonly FEATURE_SLUG="$1"
readonly PHASE="$2"
[[ "$FEATURE_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || usage
[[ "$PHASE" == "before" || "$PHASE" == "after" ]] || usage

readonly RUN_DIR="$REPOSITORY_ROOT/diagnostics/mac-ui/$FEATURE_SLUG"
readonly MARKER_PATH="$RUN_DIR/.run-start-marker"
readonly DESTINATION_PATH="$RUN_DIR/$PHASE.png"

if [[ ! -f "$MARKER_PATH" ]]; then
  echo "BLOCKED: start the run before collecting screenshots" >&2
  exit 1
fi

if [[ -e "$DESTINATION_PATH" ]]; then
  echo "BLOCKED: $DESTINATION_PATH already exists; refusing to replace evidence" >&2
  exit 1
fi

configured_location="$(defaults read com.apple.screencapture location 2>/dev/null || true)"
if [[ -z "$configured_location" ]]; then
  configured_location="$HOME/Desktop"
elif [[ "$configured_location" == "~" ]]; then
  configured_location="$HOME"
elif [[ "$configured_location" == "~/"* ]]; then
  configured_location="$HOME/${configured_location#~/}"
fi

if [[ ! -d "$configured_location" ]]; then
  echo "BLOCKED: macOS screenshot directory does not exist: $configured_location" >&2
  exit 1
fi

latest_record="$(find "$configured_location" -maxdepth 1 -type f -name '*.png' -newer "$MARKER_PATH" -exec stat -f '%m|%N' {} \; | sort -rn | sed -n '1p')"
if [[ -z "$latest_record" ]]; then
  echo "BLOCKED: no new PNG was found; press Cmd+Shift+3 through Computer Use, then retry" >&2
  exit 1
fi

source_path="${latest_record#*|}"
if [[ ! -r "$source_path" ]]; then
  echo "BLOCKED: latest screenshot is not readable: $source_path" >&2
  exit 1
fi

temporary_destination="$(mktemp "$RUN_DIR/$PHASE.png.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_destination:-}" && -f "$temporary_destination" ]]; then
    rm -f "$temporary_destination"
  fi
}
trap cleanup EXIT

cp -p "$source_path" "$temporary_destination"
if ! sips -g format "$temporary_destination" 2>/dev/null | grep -q 'format: png'; then
  echo "BLOCKED: collected file is not a valid PNG screenshot" >&2
  exit 1
fi
mv "$temporary_destination" "$DESTINATION_PATH"
temporary_destination=""

echo "Collected $PHASE screenshot: $DESTINATION_PATH"
echo "Source: $source_path"
