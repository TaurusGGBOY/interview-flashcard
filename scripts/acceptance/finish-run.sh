#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"

usage() {
  echo "Usage: scripts/acceptance/finish-run.sh <feature-slug>" >&2
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
: "${IF_SIMULATOR_UDID:?missing IF_SIMULATOR_UDID}"
: "${IF_SIMULATOR_RUNTIME:?missing IF_SIMULATOR_RUNTIME}"
: "${IF_BUNDLE_ID:?missing IF_BUNDLE_ID}"

readonly RUN_DIR="$REPOSITORY_ROOT/diagnostics/mac-ui/$FEATURE_SLUG"
readonly CONTEXT_PATH="$RUN_DIR/context.txt"

missing=0
for evidence_name in context.txt tests.log build.log launch.log steps.md before.png after.png state.json; do
  if [[ ! -s "$RUN_DIR/$evidence_name" ]]; then
    echo "FAILED: missing or empty evidence: $RUN_DIR/$evidence_name" >&2
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] || exit 1

recorded_commit="$(sed -n 's/^git_commit=//p' "$CONTEXT_PATH")"
current_commit="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
if [[ "$recorded_commit" != "$current_commit" ]]; then
  echo "FAILED: evidence commit $recorded_commit does not match current checkout $current_commit" >&2
  exit 1
fi

grep -Fxq "simulator_udid=$IF_SIMULATOR_UDID" "$CONTEXT_PATH" || {
  echo "FAILED: Simulator UDID does not match the run context" >&2
  exit 1
}
grep -Fxq "simulator_runtime=$IF_SIMULATOR_RUNTIME" "$CONTEXT_PATH" || {
  echo "FAILED: Simulator runtime does not match the run context" >&2
  exit 1
}
grep -Fxq "bundle_id=$IF_BUNDLE_ID" "$CONTEXT_PATH" || {
  echo "FAILED: bundle ID does not match the run context" >&2
  exit 1
}

grep -q 'TEST SUCCEEDED' "$RUN_DIR/tests.log" || {
  echo "FAILED: tests.log does not contain TEST SUCCEEDED" >&2
  exit 1
}
grep -q 'BUILD SUCCEEDED' "$RUN_DIR/build.log" || {
  echo "FAILED: build.log does not contain BUILD SUCCEEDED" >&2
  exit 1
}
grep -q "$IF_BUNDLE_ID" "$RUN_DIR/launch.log" || {
  echo "FAILED: launch.log does not identify $IF_BUNDLE_ID" >&2
  exit 1
}
grep -Eq '^- Acceptance result:[[:space:]]*PASS[[:space:]]*$' "$RUN_DIR/steps.md" || {
  echo "FAILED: steps.md must end the completed review with '- Acceptance result: PASS'" >&2
  exit 1
}

for screenshot_name in before.png after.png; do
  if ! sips -g format "$RUN_DIR/$screenshot_name" 2>/dev/null | grep -q 'format: png'; then
    echo "FAILED: $screenshot_name is not a valid PNG" >&2
    exit 1
  fi
done
plutil -lint "$RUN_DIR/state.json" >/dev/null || {
  echo "FAILED: state.json is not valid JSON" >&2
  exit 1
}

echo "PASS: acceptance evidence is complete for $FEATURE_SLUG"
echo "Evidence: $RUN_DIR"
