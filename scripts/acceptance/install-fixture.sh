#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"
readonly FIXTURE_ROOT="$REPOSITORY_ROOT/Tests/Fixtures"

if [[ ! -r "$ACCEPTANCE_ENV_PATH" ]]; then
  echo "BLOCKED: run scripts/dev/preflight.sh successfully first" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ACCEPTANCE_ENV_PATH"
: "${INTERVIEW_XCODE_DEVELOPER_DIR:?missing INTERVIEW_XCODE_DEVELOPER_DIR}"
: "${IF_SIMULATOR_UDID:?missing IF_SIMULATOR_UDID}"
: "${IF_BUNDLE_ID:?missing IF_BUNDLE_ID}"

if [[ $# -eq 0 ]]; then
  fixture_names=(sample-interview.md long-interview.md)
else
  fixture_names=("$@")
fi

readonly APP_DATA_CONTAINER="$(
  DEVELOPER_DIR="$INTERVIEW_XCODE_DEVELOPER_DIR" \
    "$INTERVIEW_XCODE_DEVELOPER_DIR/usr/bin/xcrun" simctl get_app_container \
    "$IF_SIMULATOR_UDID" "$IF_BUNDLE_ID" data
)"
readonly DESTINATION="$APP_DATA_CONTAINER/Documents/Acceptance"
mkdir -p "$DESTINATION"

for fixture_name in "${fixture_names[@]}"; do
  if [[ "$fixture_name" != "$(basename "$fixture_name")" || ! "$fixture_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.md$ ]]; then
    echo "Invalid fixture name: $fixture_name" >&2
    exit 2
  fi
  source_path="$FIXTURE_ROOT/$fixture_name"
  if [[ ! -f "$source_path" ]]; then
    echo "Fixture not found: $source_path" >&2
    exit 1
  fi
  cp "$source_path" "$DESTINATION/$fixture_name"
  echo "Installed $fixture_name to Documents/Acceptance"
done
