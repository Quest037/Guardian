#!/usr/bin/env bash
# Copy design PNGs from Guardian/Resources/SimulationDevices into the SwiftPM-bundled folder
# Sources/GuardianHQ/Resources/SimulationDevices (Dev_Sim_<type>.png).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/SimulationDevices"
DST="$ROOT/Sources/GuardianHQ/Resources/SimulationDevices"
if [[ ! -d "$SRC" ]]; then
  echo "sync: missing $SRC" >&2
  exit 1
fi
mkdir -p "$DST"
shopt -s nullglob
files=( "$SRC"/Dev_Sim_*.png )
if [[ ${#files[@]} -eq 0 ]]; then
  echo "sync: no Dev_Sim_*.png in $SRC" >&2
  exit 1
fi
cp -f "${files[@]}" "$DST/"
echo "sync: copied ${#files[@]} file(s) to $DST"
