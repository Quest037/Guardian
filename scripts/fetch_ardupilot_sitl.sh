#!/usr/bin/env bash
# Clones ArduPilot into Sources/GuardianHQ/Resources/ArduPilotSitl so Guardian can run
# Tools/autotest/sim_vehicle.py from the app bundle (same pattern as mavsdk_server).
#
# ArduPilot is GPLv3 — comply with its license when you distribute binaries that include this tree.
#
# Usage:
#   ./scripts/fetch_ardupilot_sitl.sh
# Optional:
#   ARDUPILOT_TAG=Copter-4.6.0 ./scripts/fetch_ardupilot_sitl.sh
#
# Requires: git, rsync, and network access. Submodule init can take several minutes on first run.

set -euo pipefail

TAG="${ARDUPILOT_TAG:-Copter-4.6.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/GuardianHQ/Resources/ArduPilotSitl"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$DEST"

apply_guardian_waf_git_patch() {
  local py="$ROOT/scripts/patch_ardupilot_waf_git_fallback.py"
  local target="$DEST/Tools/ardupilotwaf/git_submodule.py"
  if [[ -f "$py" ]] && [[ -f "$target" ]]; then
    python3 "$py" "$target"
  fi
}

if [[ -f "$DEST/Tools/autotest/sim_vehicle.py" ]] && [[ -f "$DEST/.guardian_ardupilot_tag" ]] && [[ "$(cat "$DEST/.guardian_ardupilot_tag")" == "$TAG" ]]; then
  echo "ArduPilot SITL bundle already present at tag $TAG."
  apply_guardian_waf_git_patch
  exit 0
fi

echo "Cloning ArduPilot $TAG (shallow) …"
git clone --depth 1 --branch "$TAG" https://github.com/ArduPilot/ardupilot.git "$TMP/ap"

echo "Initializing submodules (required for sim_vehicle / pymavlink) …"
(
  cd "$TMP/ap"
  git submodule update --init --recursive
)

echo "Syncing into $DEST …"
rm -rf "$DEST"
mkdir -p "$DEST"
rsync -a "$TMP/ap/" "$DEST/"

# Same text as Sources/GuardianHQ/Resources/ArduPilotSitl/_GUARDIAN_DO_NOT_DELETE.txt in git (do not use
# `git checkout` here — it fails if the file is not committed yet or this tree is not a git checkout).
cat > "$DEST/_GUARDIAN_DO_NOT_DELETE.txt" <<'ENDGUARDIAN'
Guardian keeps this file so the ArduPilotSitl resource folder exists in git and SwiftPM can bundle it.
Populate the rest of this directory by running: ./scripts/fetch_ardupilot_sitl.sh (or: make sitl-runtime).
ENDGUARDIAN

printf '%s\n' "$TAG" > "$DEST/.guardian_ardupilot_tag"

echo "Verifying sim_vehicle.py …"
test -f "$DEST/Tools/autotest/sim_vehicle.py"
apply_guardian_waf_git_patch
echo "Done: ArduPilot SITL bundle at $DEST (tag $TAG)."
echo "Next: from the Guardian repo run 'make sitl-deps' (pexpect, empy, gnureadline for sim_vehicle / waf / MAVProxy) and install MAVProxy (pip3 install MAVProxy)."
