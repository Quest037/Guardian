#!/usr/bin/env bash
# Build a proper Guardian HQ.app so User Notifications (UNUserNotificationCenter) work.
# Flat executables under DerivedData/.../Build/Products/Debug get UNErrorDomain code 1 (notificationsNotAllowed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
if [[ "$CONFIG" == "release" ]]; then
  SWIFT_CONFIG="release"
else
  SWIFT_CONFIG="debug"
fi

echo "swift build -c $SWIFT_CONFIG --product GuardianHQ"
swift build -c "$SWIFT_CONFIG" --product GuardianHQ

BIN_DIR="$(swift build -c "$SWIFT_CONFIG" --show-bin-path)"
BIN="$BIN_DIR/GuardianHQ"
APP_DIR="$ROOT/build"
APP="$APP_DIR/Guardian HQ.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/GuardianHQ"
chmod +x "$APP/Contents/MacOS/GuardianHQ"
cp "$ROOT/Packaging/GuardianHQ-App-Info.plist" "$APP/Contents/Info.plist"

# SwiftPM resource bundle must live next to the executable (Bundle.module).
BUNDLE="$BIN_DIR/GuardianHQ_GuardianHQ.bundle"
if [[ -d "$BUNDLE" ]]; then
  rm -rf "$APP/Contents/MacOS/GuardianHQ_GuardianHQ.bundle"
  cp -R "$BUNDLE" "$APP/Contents/MacOS/"
fi

ICON_SRC="$ROOT/Sources/GuardianHQ/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "Built: $APP"
echo "Run: open \"$APP\""
