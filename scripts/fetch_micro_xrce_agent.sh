#!/usr/bin/env bash
# Places MicroXRCEAgent in Sources/GuardianHQ/Resources/Ros2Runtime/bin/ for app bundling.
#
# Usage:
#   ./scripts/fetch_micro_xrce_agent.sh
#
# PX4-aligned tag v2.4.3 (see docs.px4.io middleware uXRCE-DDS). Tries Homebrew/PATH,
# then builds from source. On Apple Silicon, host-arch only unless
# GUARDIAN_MICROXRCE_UNIVERSAL=1.

set -euo pipefail

VERSION="${MICROXRCE_VERSION:-v2.4.3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_BIN="$ROOT/Sources/GuardianHQ/Resources/Ros2Runtime/bin"
OUT="$DEST_BIN/MicroXRCEAgent"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$DEST_BIN"

find_built_agent() {
  find "$1" -type f \( -name MicroXRCEAgent -o -name micro-xrce-dds-agent \) -perm +111 2>/dev/null | head -1
}

try_homebrew() {
  local prefix=""
  if command -v brew >/dev/null 2>&1; then
    prefix="$(brew --prefix micro-xrce-dds-agent 2>/dev/null || true)"
  fi
  if [[ -n "$prefix" ]] && [[ -x "$prefix/bin/MicroXRCEAgent" ]]; then
    echo "Copying MicroXRCEAgent from Homebrew ($prefix) …"
    cp "$prefix/bin/MicroXRCEAgent" "$OUT"
    chmod +x "$OUT"
    return 0
  fi
  if command -v MicroXRCEAgent >/dev/null 2>&1; then
    echo "Copying MicroXRCEAgent from PATH …"
    cp "$(command -v MicroXRCEAgent)" "$OUT"
    chmod +x "$OUT"
    return 0
  fi
  return 1
}

bundle_macos_agent() {
  local build_dir="$1"
  local exe_src="$2"
  local dest_exe="$3"
  local lib_dir
  lib_dir="$(cd "$(dirname "$dest_exe")/.." && pwd)/lib"
  mkdir -p "$lib_dir"

  find "$build_dir" -name '*.dylib' -type f -exec cp -f {} "$lib_dir/" \;
  cp -f "$exe_src" "$dest_exe"
  chmod +x "$dest_exe"

  resolve_lib_basename() {
    local dep_name="$1"
    if [[ -f "$lib_dir/$dep_name" ]]; then
      echo "$dep_name"
      return 0
    fi
    local stem="${dep_name%.dylib}"
    local match
    match="$(find "$lib_dir" -maxdepth 1 -name "${stem}*.dylib" -type f 2>/dev/null | head -1)"
    if [[ -n "$match" ]]; then
      basename "$match"
      return 0
    fi
    return 1
  }

  fix_deps() {
    local target="$1"
    local id_path
    if [[ "$target" == *.dylib ]]; then
      id_path="@loader_path/$(basename "$target")"
      install_name_tool -id "$id_path" "$target" 2>/dev/null || true
    fi
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      case "$dep" in
        /usr/lib/* | /System/* | @loader_path/* | @executable_path/*) continue ;;
      esac
      local base
      base="$(resolve_lib_basename "${dep##*/}")" || continue
      if [[ "$target" == *.dylib ]]; then
        install_name_tool -change "$dep" "@loader_path/$base" "$target" 2>/dev/null || true
      else
        install_name_tool -change "$dep" "@executable_path/../lib/$base" "$target" 2>/dev/null || true
      fi
    done < <(otool -L "$target" 2>/dev/null | tail -n +2 | awk '{print $1}')
  }

  local lib
  for lib in "$lib_dir"/*.dylib; do
    [[ -f "$lib" ]] || continue
    fix_deps "$lib"
  done
  install_name_tool -add_rpath @executable_path/../lib "$dest_exe" 2>/dev/null || true
  fix_deps "$dest_exe"
}

patch_agent_superbuild_macos() {
  # Nested uagent build can leave CMAKE_SYSTEM_NAME empty and compile Linux CAN code on macOS.
  local sb="$1/cmake/SuperBuild.cmake"
  if grep -q 'GUARDIAN_UAGENT_DARWIN_OPTS' "$sb"; then
    return 0
  fi
  perl -0pi -e 's/(-DUAGENT_SUPERBUILD:BOOL=OFF\n)/$1        -DUAGENT_SOCKETCAN_PROFILE:BOOL=OFF # GUARDIAN_UAGENT_DARWIN_OPTS\n        -DCMAKE_SYSTEM_NAME:STRING=Darwin\n/s' "$sb"
}

host_arch() {
  uname -m
}

want_universal() {
  [[ "${GUARDIAN_MICROXRCE_UNIVERSAL:-}" == "1" ]]
}

build_from_source() {
  echo "Building Micro-XRCE-DDS-Agent $VERSION from source (PX4-aligned) …"
  git clone --depth 1 --branch "$VERSION" https://github.com/eProsima/Micro-XRCE-DDS-Agent.git "$TMP/src"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    patch_agent_superbuild_macos "$TMP/src"
  fi

  build_one() {
    local arch="$1"
    local build_dir="$TMP/build-$arch"
    local bin
    local cmake_args=(
      -S "$TMP/src"
      -B "$build_dir"
      -DCMAKE_BUILD_TYPE=Release
      -DUAGENT_SUPERBUILD=ON
      -DUAGENT_BUILD_TESTS=OFF
      -DUAGENT_BUILD_EXECUTABLE=ON
    )
    if [[ "$(uname -s)" == "Darwin" ]]; then
      cmake_args+=(
        -DCMAKE_OSX_ARCHITECTURES="$arch"
        -DCMAKE_SYSTEM_NAME=Darwin
        -DUAGENT_SOCKETCAN_PROFILE=OFF
      )
    fi
    cmake "${cmake_args[@]}" >&2
    cmake --build "$build_dir" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)" >&2
    bin="$(find_built_agent "$build_dir")"
    if [[ -z "$bin" ]]; then
      echo "error: MicroXRCEAgent not found under $build_dir" >&2
      return 1
    fi
    printf '%s|%s\n' "$bin" "$build_dir"
  }

  install_built_agent() {
    local result="$1"
    local bin="${result%%|*}"
    local build_dir="${result##*|}"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      bundle_macos_agent "$build_dir" "$bin" "$OUT"
    else
      cp -f "$bin" "$OUT"
      chmod +x "$OUT"
    fi
  }

  local host
  host="$(host_arch)"
  if want_universal && [[ "$(uname -s)" == "Darwin" ]]; then
    echo "error: GUARDIAN_MICROXRCE_UNIVERSAL=1 is not supported yet; build host arch only" >&2
    return 1
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    local arch="arm64"
    if [[ "$host" == "x86_64" ]]; then
      arch="x86_64"
    fi
    install_built_agent "$(build_one "$arch")"
  else
    install_built_agent "$(build_one "$host")"
  fi
}

if [[ -x "$OUT" ]] && [[ "${GUARDIAN_FORCE_MICROXRCE_FETCH:-}" != "1" ]]; then
  echo "MicroXRCEAgent already present at $OUT"
  exit 0
fi

if try_homebrew; then
  :
elif build_from_source; then
  :
else
  echo "error: could not obtain MicroXRCEAgent" >&2
  exit 1
fi

echo "Done: $OUT ($(file -b "$OUT"))"
