#!/usr/bin/env bash
# Shallow-clone PX4 (docs only via sparse checkout) and ArduPilot wiki into Resources/StackWiki/upstream/.
#
# Usage:
#   ./scripts/stack_wiki/fetch_upstream.sh
# Optional:
#   STACK_WIKI_PX4_REF=main STACK_WIKI_ARDUPILOT_REF=master ./scripts/stack_wiki/fetch_upstream.sh
#
# Requires: git, network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM="$ROOT/Resources/StackWiki/upstream"
PX4_REF="${STACK_WIKI_PX4_REF:-main}"
AP_REF="${STACK_WIKI_ARDUPILOT_REF:-master}"
PX4_DIR="$UPSTREAM/PX4-Autopilot"
AP_DIR="$UPSTREAM/ardupilot_wiki"

mkdir -p "$UPSTREAM"

fetch_px4() {
  if [[ -d "$PX4_DIR/.git" ]]; then
    echo "Updating PX4-Autopilot (ref $PX4_REF) …"
    git -C "$PX4_DIR" fetch --depth 1 origin "$PX4_REF"
    git -C "$PX4_DIR" checkout -f FETCH_HEAD
    git -C "$PX4_DIR" sparse-checkout set docs
  else
    echo "Cloning PX4-Autopilot (sparse: docs/) …"
    rm -rf "$PX4_DIR"
    git clone --depth 1 --branch "$PX4_REF" --filter=blob:none --sparse \
      https://github.com/PX4/PX4-Autopilot.git "$PX4_DIR"
    git -C "$PX4_DIR" sparse-checkout set docs
  fi
  if [[ ! -d "$PX4_DIR/docs/en" ]]; then
    echo "error: expected $PX4_DIR/docs/en after sparse checkout" >&2
    exit 1
  fi
  echo "PX4 docs commit: $(git -C "$PX4_DIR" rev-parse HEAD)"
}

fetch_ardupilot_wiki() {
  if [[ -d "$AP_DIR/.git" ]]; then
    echo "Updating ardupilot_wiki (ref $AP_REF) …"
    git -C "$AP_DIR" fetch --depth 1 origin "$AP_REF"
    git -C "$AP_DIR" checkout -f FETCH_HEAD
  else
    echo "Cloning ardupilot_wiki …"
    rm -rf "$AP_DIR"
    git clone --depth 1 --branch "$AP_REF" \
      https://github.com/ArduPilot/ardupilot_wiki.git "$AP_DIR"
  fi
  echo "ArduPilot wiki commit: $(git -C "$AP_DIR" rev-parse HEAD)"
}

fetch_px4
fetch_ardupilot_wiki
echo "Stack wiki upstream ready under $UPSTREAM"
