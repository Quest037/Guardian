#!/usr/bin/env bash
# Downloads official MAVSDK release binaries and builds a universal macOS
# `mavsdk_server` next to other Guardian resources (for bundling in the app).
#
# Usage:
#   ./scripts/fetch_mavsdk_server.sh
# Optional:
#   MAVSDK_VERSION=3.17.1 ./scripts/fetch_mavsdk_server.sh
#
# Before shipping a signed/notarized Guardian build, sign this binary with the
# same Developer ID as the app (see scripts/codesign_bundled_mavsdk_server.sh).

set -euo pipefail

VERSION="${MAVSDK_VERSION:-3.17.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/Sources/GuardianHQ/Resources"
OUT="$RES/mavsdk_server"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$RES"
BASE="https://github.com/mavlink/MAVSDK/releases/download/v${VERSION}"

echo "Fetching mavsdk_server v${VERSION} (macOS arm64 + x64)…"
curl -fsSL "$BASE/mavsdk_server_macos_arm64" -o "$TMP/arm64"
curl -fsSL "$BASE/mavsdk_server_macos_x64" -o "$TMP/x64"
chmod +x "$TMP/arm64" "$TMP/x64"

echo "Creating universal binary at $OUT"
lipo -create -output "$OUT" "$TMP/arm64" "$TMP/x64"
chmod +x "$OUT"

echo "Done: $(ls -lh "$OUT" | awk '{print $5, $9}')"
