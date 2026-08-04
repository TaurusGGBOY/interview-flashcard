#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "== InterviewFlashcard final checks =="

if ! "$REPOSITORY_ROOT/scripts/dev/preflight.sh"; then
  echo "BLOCKED: full Xcode/iOS Simulator preflight did not pass; static checks continue." >&2
  static_only="true"
else
  static_only="false"
fi

bash -n "$REPOSITORY_ROOT/scripts/dev/preflight.sh" \
  "$REPOSITORY_ROOT/scripts/dev/test.sh" \
  "$REPOSITORY_ROOT/scripts/dev/build-and-launch.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/start-run.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/collect-screenshot.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/read-state.sh" \
  "$REPOSITORY_ROOT/scripts/acceptance/finish-run.sh"

while IFS= read -r -d '' swift_file; do
  swiftc -frontend -parse "$swift_file" >/dev/null
done < <(find "$REPOSITORY_ROOT/InterviewFlashcard" "$REPOSITORY_ROOT/InterviewFlashcardTests" -type f -name '*.swift' -print0)

if [[ "$static_only" == "false" ]]; then
  "$REPOSITORY_ROOT/scripts/dev/test.sh"
  IF_BUILD_LOG_PATH="$REPOSITORY_ROOT/.build/logs/final-build.log" \
    IF_LAUNCH_LOG_PATH="$REPOSITORY_ROOT/.build/logs/final-launch.log" \
    "$REPOSITORY_ROOT/scripts/dev/build-and-launch.sh" \
      --ai stub --stub-mode success --speech unsupported --fixture mvp-workflow
fi

for path in "$REPOSITORY_ROOT"/build.log "$REPOSITORY_ROOT"/launch.log "$REPOSITORY_ROOT"/diagnostics; do
  [[ -e "$path" ]] || continue
  if rg -n -i 'Authorization:[[:space:]]*Bearer|secret-marker|\.m4a' "$path"; then
    echo "FAILED: sensitive token or audio upload marker found in $path" >&2
    exit 1
  fi
done

if git -C "$REPOSITORY_ROOT" status --short --untracked-files=all | rg -n '(^|[[:space:]])InterviewFlashcard\.xcodeproj/' ; then
  echo "FAILED: generated Xcode project contains unignored files" >&2
  exit 1
fi

echo "PASS: static source/script checks completed"
if [[ "$static_only" == "true" ]]; then
  echo "NOTE: build/test/Computer Use remain blocked until full Xcode and an iOS Simulator are installed."
fi
