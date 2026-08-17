#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ai_provider=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deepseek|--cc-switch)
      ai_provider="${1#--}"
      shift
      ;;
    --help|-h)
      cat >&2 <<'USAGE'
Usage: scripts/dev/open-app.sh [--cc-switch|--deepseek]

Builds the current checkout, installs it on the pinned iPhone 17 Pro Max
Simulator, and launches the app without deleting existing app data.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ai_provider" ]]; then
  ai_provider="cc-switch"
fi

echo "Opening InterviewFlashcard from $REPOSITORY_ROOT"
echo "AI provider: $ai_provider"

exec "$REPOSITORY_ROOT/scripts/dev/build-and-launch.sh" \
  --ai "$ai_provider" \
  --keep-data
