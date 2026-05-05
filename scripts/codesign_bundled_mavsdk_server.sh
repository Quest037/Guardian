#!/usr/bin/env bash
# Sign the bundled mavsdk_server for distribution (Developer ID + hardened runtime).
# Notarization requires every executable in the app bundle to be signed.
#
# Prerequisites:
#   - Apple Developer "Developer ID Application" certificate installed
#   - For notarization: also sign the outer .app and run `xcrun notarytool submit`
#
# Usage:
#   export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   ./scripts/codesign_bundled_mavsdk_server.sh
#
# You can also point at the copy inside a built .app:
#   CODESIGN_TARGET="build/GuardianHQ.app/Contents/Resources/mavsdk_server" ./scripts/codesign_bundled_mavsdk_server.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${CODESIGN_TARGET:-$ROOT/Sources/GuardianHQ/Resources/mavsdk_server}"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Set CODESIGN_IDENTITY to your Developer ID Application signing identity." >&2
  echo "Example: export CODESIGN_IDENTITY=\"Developer ID Application: …\"" >&2
  exit 1
fi

if [[ ! -f "$TARGET" ]]; then
  echo "Missing $TARGET — run ./scripts/fetch_mavsdk_server.sh first." >&2
  exit 1
fi

codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$TARGET"
echo "Signed: $TARGET"
codesign -dv --verbose=4 "$TARGET" 2>&1 | head -20
