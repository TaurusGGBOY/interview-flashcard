#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ACCEPTANCE_ENV_PATH="$REPOSITORY_ROOT/.local/acceptance.env"

usage() {
  echo "Usage: scripts/acceptance/start-run.sh <feature-slug>" >&2
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
: "${IF_SIMULATOR_NAME:?missing IF_SIMULATOR_NAME}"
: "${IF_SIMULATOR_RUNTIME:?missing IF_SIMULATOR_RUNTIME}"
: "${IF_BUNDLE_ID:?missing IF_BUNDLE_ID}"

readonly RUN_DIR="$REPOSITORY_ROOT/diagnostics/mac-ui/$FEATURE_SLUG"
readonly CONTEXT_PATH="$RUN_DIR/context.txt"
readonly MARKER_PATH="$RUN_DIR/.run-start-marker"

mkdir -p "$RUN_DIR"

for evidence_name in context.txt tests.log build.log launch.log steps.md before.png after.png state.json; do
  if [[ -e "$RUN_DIR/$evidence_name" ]]; then
    echo "BLOCKED: $RUN_DIR already contains evidence; archive it before starting a new run" >&2
    exit 1
  fi
done

git_branch="$(git -C "$REPOSITORY_ROOT" branch --show-current)"
git_commit="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
worktree_status="$(git -C "$REPOSITORY_ROOT" status --short)"

temporary_context="$(mktemp "$RUN_DIR/context.txt.XXXXXX")"
cleanup() {
  if [[ -n "${temporary_context:-}" && -f "$temporary_context" ]]; then
    rm -f "$temporary_context"
  fi
}
trap cleanup EXIT

{
  printf 'started_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'repository_root=%s\n' "$REPOSITORY_ROOT"
  printf 'git_branch=%s\n' "$git_branch"
  printf 'git_commit=%s\n' "$git_commit"
  printf 'developer_dir=%s\n' "$INTERVIEW_XCODE_DEVELOPER_DIR"
  printf 'simulator_udid=%s\n' "$IF_SIMULATOR_UDID"
  printf 'simulator_name=%s\n' "$IF_SIMULATOR_NAME"
  printf 'simulator_runtime=%s\n' "$IF_SIMULATOR_RUNTIME"
  printf 'bundle_id=%s\n' "$IF_BUNDLE_ID"
  echo "worktree_status_begin"
  if [[ -n "$worktree_status" ]]; then
    printf '%s\n' "$worktree_status"
  fi
  echo "worktree_status_end"
} > "$temporary_context"

mv "$temporary_context" "$CONTEXT_PATH"
temporary_context=""
touch "$MARKER_PATH"

{
  printf '# %s Computer Use acceptance\n\n' "$FEATURE_SLUG"
  echo '- User path:'
  echo '- Visible result:'
  echo '- Independent state readback:'
  echo '- Exceptions: none'
  echo '- Acceptance result: PENDING'
} > "$RUN_DIR/steps.md"

echo "Started acceptance run: $RUN_DIR"
echo "Commit: $git_commit"
