#!/usr/bin/env bash

set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: $0 <InterviewFlashcard.app>" >&2; exit 2; }
readonly APP_PATH="$1"
readonly PLIST_PATH="$APP_PATH/Info.plist"
readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ICON_DIR="$REPO_ROOT/InterviewFlashcard/Resources/Assets.xcassets/AppIcon.appiconset"

fail() {
  echo "FAILED: $*" >&2
  exit 1
}

[[ -d "$APP_PATH" ]] || fail "app bundle missing: $APP_PATH"
[[ -f "$PLIST_PATH" ]] || fail "Info.plist missing: $PLIST_PATH"
[[ -f "$APP_PATH/Assets.car" ]] || fail "compiled asset catalog is missing: $APP_PATH/Assets.car"

for icon_path in \
  "$ICON_DIR/AppIcon-1024.png" \
  "$ICON_DIR/AppIcon-1024-dark.png" \
  "$ICON_DIR/AppIcon-1024-tinted.png"; do
  [[ -f "$icon_path" ]] || fail "icon source is missing: $icon_path"
  icon_dimensions="$(sips -g pixelWidth -g pixelHeight "$icon_path")"
  [[ "$icon_dimensions" == *"pixelWidth: 1024"* && "$icon_dimensions" == *"pixelHeight: 1024"* ]] \
    || fail "icon source must be 1024x1024: $icon_path"
  [[ "$(sips -g hasAlpha "$icon_path" | awk '/hasAlpha/ {print $2}')" == "no" ]] \
    || fail "icon source must not have an alpha channel: $icon_path"
done

icon_name=""
for icon_key in \
  ':CFBundleIcons~iphone:CFBundlePrimaryIcon:CFBundleIconName' \
  ':CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName'; do
  if icon_name="$($PLIST_BUDDY -c "Print $icon_key" "$PLIST_PATH" 2>/dev/null)"; then
    break
  fi
  icon_name=""
done
[[ "$icon_name" == "AppIcon" ]] || fail "compiled app icon name must be AppIcon"

"$PLIST_BUDDY" -c 'Print :UILaunchScreen' "$PLIST_PATH" >/dev/null \
  || fail "UILaunchScreen is missing"
"$PLIST_BUDDY" -c 'Print :UIApplicationSceneManifest' "$PLIST_PATH" >/dev/null \
  || fail "UIApplicationSceneManifest is missing"
[[ "$("$PLIST_BUDDY" -c 'Print :UIDeviceFamily:0' "$PLIST_PATH")" == "1" ]] \
  || fail "UIDeviceFamily[0] must be iPhone"
if "$PLIST_BUDDY" -c 'Print :UIDeviceFamily:1' "$PLIST_PATH" >/dev/null 2>&1; then
  fail "application target must not include iPad"
fi
[[ "$("$PLIST_BUDDY" -c 'Print :UISupportedInterfaceOrientations~iphone:0' "$PLIST_PATH")" == "UIInterfaceOrientationPortrait" ]] \
  || fail "the first supported iPhone orientation must be portrait"

if "$PLIST_BUDDY" -c 'Print :UISupportedInterfaceOrientations~iphone:1' "$PLIST_PATH" >/dev/null 2>&1; then
  fail "iPhone must support portrait only"
fi

echo "PASS: iPhone launch metadata and app icon assets are valid"
