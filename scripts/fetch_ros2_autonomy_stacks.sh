#!/usr/bin/env bash
# Shallow-clone Nav2, Aerostack2, and as2_platform_pixhawk into
# Sources/GuardianHQ/Resources/Ros2AutonomyStacks/upstream/.
#
# Usage:
#   ./scripts/fetch_ros2_autonomy_stacks.sh
# Optional env (overrides manifest.json refs):
#   GUARDIAN_ROS2_DISTRO=humble
#   GUARDIAN_NAV2_REF=humble
#   GUARDIAN_AEROSTACK2_REF=main
#   GUARDIAN_AS2_PLATFORM_PIXHAWK_REF=main
#
# Requires: git, python3, network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACKS_ROOT="$ROOT/Sources/GuardianHQ/Resources/Ros2AutonomyStacks"
MANIFEST="$STACKS_ROOT/manifest.json"
UPSTREAM="$STACKS_ROOT/upstream"
LOCK_FILE="$STACKS_ROOT/.guardian_ros2_autonomy_lock"

mkdir -p "$UPSTREAM"

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: missing manifest at $MANIFEST" >&2
  exit 1
fi

export GUARDIAN_ROS2_DISTRO="${GUARDIAN_ROS2_DISTRO:-}"
export GUARDIAN_NAV2_REF="${GUARDIAN_NAV2_REF:-}"
export GUARDIAN_AEROSTACK2_REF="${GUARDIAN_AEROSTACK2_REF:-}"
export GUARDIAN_AS2_PLATFORM_PIXHAWK_REF="${GUARDIAN_AS2_PLATFORM_PIXHAWK_REF:-}"
export GUARDIAN_PX4_MSGS_REF="${GUARDIAN_PX4_MSGS_REF:-}"

clone_or_update() {
  local id="$1" url="$2" ref="$3" dir="$4" verify_rel="$5"
  local dest="$UPSTREAM/$dir"

  if [[ -d "$dest/.git" ]]; then
    echo "Updating $id (ref $ref) …" >&2
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" checkout -f FETCH_HEAD
  else
    echo "Cloning $id (ref $ref) …" >&2
    rm -rf "$dest"
    git clone --depth 1 --branch "$ref" "$url" "$dest"
  fi

  if [[ ! -f "$dest/$verify_rel" ]]; then
    echo "error: expected $dest/$verify_rel after checkout" >&2
    exit 1
  fi
  local sha
  sha="$(git -C "$dest" rev-parse HEAD)"
  echo "$id commit: $sha" >&2
  printf '%s\n' "$sha"
}

ROS_DISTRO="$(
  python3 - "$MANIFEST" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print(os.environ.get("GUARDIAN_ROS2_DISTRO") or data.get("ros_distro", "humble"))
PY
)"

echo "ROS distro lock: $ROS_DISTRO"

{
  echo "# Written by scripts/fetch_ros2_autonomy_stacks.sh — do not edit by hand."
  echo "ros_distro=$ROS_DISTRO"
  echo "fetched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  while IFS=$'\t' read -r id url ref dir verify; do
    sha="$(clone_or_update "$id" "$url" "$ref" "$dir" "$verify")"
    echo "${id}=${sha}"
  done < <(
    python3 - "$MANIFEST" <<'PY'
import json, os, sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

overrides = {
    "navigation2": os.environ.get("GUARDIAN_NAV2_REF"),
    "aerostack2": os.environ.get("GUARDIAN_AEROSTACK2_REF"),
    "as2_platform_pixhawk": os.environ.get("GUARDIAN_AS2_PLATFORM_PIXHAWK_REF"),
    "px4_msgs": os.environ.get("GUARDIAN_PX4_MSGS_REF"),
}

for repo in data["repos"]:
    rid = repo["id"]
    ref = overrides.get(rid) or repo["ref"]
    print(
        "\t".join(
            [
                rid,
                repo["url"],
                ref,
                repo["dir"],
                repo["verify_path"],
            ]
        )
    )
PY
  )
} | tee "$LOCK_FILE"

echo "ROS 2 autonomy stacks ready under $UPSTREAM"
