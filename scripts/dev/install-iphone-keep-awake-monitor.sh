#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
PLIST_SOURCE="$SCRIPT_DIR/com.gaoguobin.interviewflashcard.iphone-keep-awake.plist"
MONITOR_SOURCE="$SCRIPT_DIR/monitor-iphone-connection.sh"
LABEL="com.gaoguobin.interviewflashcard.iphone-keep-awake"
PLIST_TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
MONITOR_TARGET="$HOME/Library/Application Support/InterviewFlashcard/monitor-iphone-connection.sh"
GUI_DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true
  if [[ -e "$PLIST_TARGET" ]]; then
    rm -f "$PLIST_TARGET"
  fi
  if [[ -e "$MONITOR_TARGET" ]]; then
    rm -f "$MONITOR_TARGET"
  fi
  echo "Removed $LABEL."
  exit 0
fi

if [[ ! -x "$SCRIPT_DIR/monitor-iphone-connection.sh" ]]; then
  echo "Monitor script is not executable: $SCRIPT_DIR/monitor-iphone-connection.sh" >&2
  exit 2
fi

mkdir -p "$(dirname -- "$PLIST_TARGET")"
mkdir -p "$(dirname -- "$MONITOR_TARGET")"
launchctl bootout "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true
cp "$PLIST_SOURCE" "$PLIST_TARGET"
cp "$MONITOR_SOURCE" "$MONITOR_TARGET"
chmod 700 "$MONITOR_TARGET"
launchctl bootstrap "$GUI_DOMAIN" "$PLIST_TARGET"
launchctl enable "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl kickstart -k "$GUI_DOMAIN/$LABEL"

echo "Installed and started $LABEL."
echo "It monitors only physical iPhone UDID 00008150-00096D3C3621401C."
echo "No password or iPhone system Auto-Lock setting is changed."
