#!/usr/bin/env bash
# Build a proper Guardian HQ.app so User Notifications (UNUserNotificationCenter) work.
# Flat executables under DerivedData/.../Build/Products/Debug get UNErrorDomain code 1 (notificationsNotAllowed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-debug}"
PRODUCT="${2:-GuardianHQ}"
if [[ "$CONFIG" == "release" ]]; then
  SWIFT_CONFIG="release"
else
  SWIFT_CONFIG="debug"
fi

case "$PRODUCT" in
  GuardianHQ|GuardianHQRun)
    SPM_PRODUCT="GuardianHQ"
    APP_NAME="Guardian HQ"
    EXEC_NAME="GuardianHQ"
    DOCK_LOGO_PNG="$ROOT/Resources/dock_logo_mission.png"
    ;;
  GuardianMission)
    SPM_PRODUCT="GuardianMission"
    APP_NAME="Guardian Mission"
    EXEC_NAME="GuardianMission"
    DOCK_LOGO_PNG="$ROOT/Resources/dock_logo_mission.png"
    ;;
  GuardianTraining)
    SPM_PRODUCT="GuardianTraining"
    APP_NAME="Guardian Training"
    EXEC_NAME="GuardianTraining"
    DOCK_LOGO_PNG="$ROOT/Resources/dock_logo_training.png"
    ;;
  *)
    echo "Unknown product: $PRODUCT (use GuardianHQ, GuardianMission, or GuardianTraining)" >&2
    exit 1
    ;;
esac

echo "swift build -c $SWIFT_CONFIG --product $SPM_PRODUCT"
swift build -c "$SWIFT_CONFIG" --product "$SPM_PRODUCT"

BIN_DIR="$(swift build -c "$SWIFT_CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$EXEC_NAME"
APP_DIR="$ROOT/build"
APP="$APP_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP/Contents/MacOS/$EXEC_NAME"
cp "$ROOT/Packaging/GuardianHQ-App-Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null || true

# SwiftPM resource bundle must live next to the executable (Bundle.module).
BUNDLE="$BIN_DIR/GuardianHQ_GuardianHQ.bundle"
if [[ -d "$BUNDLE" ]]; then
  rm -rf "$APP/Contents/MacOS/GuardianHQ_GuardianHQ.bundle"
  cp -R "$BUNDLE" "$APP/Contents/MacOS/"
  # Mission ops app: drop Training-only Gazebo assets (see README_FULL.md → Mission sim vs Training worlds).
  if [[ "$PRODUCT" == "GuardianMission" ]]; then
    MISSION_BUNDLE="$APP/Contents/MacOS/GuardianHQ_GuardianHQ.bundle"
    for training_only in GazeboRuntime GazeboWeb TrainingEnvironments; do
      if [[ -d "$MISSION_BUNDLE/$training_only" ]]; then
        rm -rf "$MISSION_BUNDLE/$training_only"
        echo "Trimmed $training_only from Mission resource bundle"
      fi
    done
  fi
fi

# Finder / Applications icon from product dock PNG (1024×1024 square).
if [[ -f "$DOCK_LOGO_PNG" ]]; then
  ICON_BUILD_DIR="$APP_DIR/.icon-build-$$"
  mkdir -p "$ICON_BUILD_DIR"
  if "$ROOT/scripts/make_app_icon.sh" "$DOCK_LOGO_PNG" "$ICON_BUILD_DIR" AppIcon; then
    cp "$ICON_BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
  else
    echo "Warning: could not build AppIcon.icns from $DOCK_LOGO_PNG" >&2
  fi
  rm -rf "$ICON_BUILD_DIR"
elif [[ -f "$ROOT/Sources/GuardianHQ/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Sources/GuardianHQ/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "Built: $APP"
echo "Run: open \"$APP\""
