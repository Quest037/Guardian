#!/usr/bin/env bash
# Bundles gzweb into one offline ESM file for World Builder (WKWebView file://).
#
# Usage: ./scripts/fetch_gzweb_viewer.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/GuardianHQ/Resources/GazeboWeb"
DIST="$DEST/dist"
BUILD="$DEST/.build"
NODE_MODULES="$BUILD/node_modules"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DIST" "$BUILD" "$NODE_MODULES"

fetch_tgz() {
  local name="$1" version="$2"
  curl -fsSL "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz" -o "$TMP/${name}.tgz"
  rm -rf "$TMP/${name}-pkg"
  mkdir -p "$TMP/${name}-pkg"
  tar -xzf "$TMP/${name}.tgz" -C "$TMP/${name}-pkg"
  echo "$TMP/${name}-pkg/package"
}

fetch_scoped_tgz() {
  local scoped="$1" version="$2"
  local scope="${scoped%%/*}"
  local name="${scoped#*/}"
  curl -fsSL "https://registry.npmjs.org/${scoped}/-/${name}-${version}.tgz" -o "$TMP/${name}.tgz"
  rm -rf "$TMP/${name}-pkg"
  mkdir -p "$TMP/${name}-pkg"
  tar -xzf "$TMP/${name}.tgz" -C "$TMP/${name}-pkg"
  echo "$TMP/${name}-pkg/package"
}

install_npm_pkg() {
  local name="$1" version="$2"
  local pkg_dir="$NODE_MODULES/$name"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"
  cp -R "$(fetch_tgz "$name" "$version")/." "$pkg_dir/"
}

install_scoped_pkg() {
  local scoped="$1" version="$2"
  local scope="${scoped%%/*}"
  local name="${scoped#*/}"
  local pkg_dir="$NODE_MODULES/$scope/$name"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir"
  cp -R "$(fetch_scoped_tgz "$scoped" "$version")/." "$pkg_dir/"
}

esbuild_bin() {
  local arch pkg ver
  arch="$(uname -m)"
  case "$arch" in
    arm64) pkg="darwin-arm64" ;;
    *) pkg="darwin-x64" ;;
  esac
  ver="0.25.5"
  local cache="$BUILD/esbuild-${pkg}-${ver}"
  if [[ ! -x "$cache/bin/esbuild" ]]; then
    rm -rf "$cache"
    mkdir -p "$cache"
    curl -fsSL "https://registry.npmjs.org/@esbuild/${pkg}/-/${pkg}-${ver}.tgz" \
      | tar -xzf - -C "$cache" --strip-components=1
  fi
  echo "$cache/bin/esbuild"
}

echo "Downloading gzweb dist…"
GZWEB_PKG="$(fetch_tgz gzweb 3.0.2)"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$GZWEB_PKG/dist/." "$DIST/"

echo "Installing npm dependencies for esbuild resolve…"
rm -rf "$NODE_MODULES"
mkdir -p "$NODE_MODULES"

install_npm_pkg three 0.141.0
install_npm_pkg eventemitter2 6.4.9
install_npm_pkg jszip 3.10.1
install_npm_pkg fast-xml-parser 4.4.1
install_npm_pkg strnum 1.0.5
install_npm_pkg three-nebula 10.0.3
install_npm_pkg rxjs 7.8.1
install_npm_pkg protobufjs 6.11.4
install_npm_pkg lodash 4.17.21
install_npm_pkg potpack 1.0.2
install_npm_pkg uuid 3.4.0
install_npm_pkg long 4.0.0
install_npm_pkg tslib 2.8.1
install_scoped_pkg @babel/runtime 7.26.0

# protobufjs expects these as separate packages (not hoisted by our manual install).
install_scoped_pkg @protobufjs/aspromise 1.1.2
install_scoped_pkg @protobufjs/base64 1.1.2
install_scoped_pkg @protobufjs/codegen 2.0.4
install_scoped_pkg @protobufjs/eventemitter 1.1.0
install_scoped_pkg @protobufjs/fetch 1.1.0
install_scoped_pkg @protobufjs/float 1.0.2
install_scoped_pkg @protobufjs/inquire 1.1.0
install_scoped_pkg @protobufjs/path 1.1.2
install_scoped_pkg @protobufjs/pool 1.1.0
install_scoped_pkg @protobufjs/utf8 1.1.0

echo "Bundling gzweb + dependencies → dist/gzweb.bundle.mjs …"
cp "$DIST/gzweb.module.js" "$BUILD/gzweb.module.js"
# gzweb uses `import * as JSZip`; jszip exports a constructor as default.
sed -i '' 's/import \* as JSZip from/import JSZip from/' "$BUILD/gzweb.module.js"

ESBUILD="$(esbuild_bin)"
(
  cd "$BUILD"
  "$ESBUILD" gzweb.module.js \
    --bundle \
    --format=esm \
    --platform=browser \
    --target=es2020 \
    --packages=bundle \
    --outfile="$DIST/gzweb.bundle.mjs" \
    --log-level=warning
)

rm -rf "$DEST/vendor" "$DEST/importmap.json"

echo "Done."
echo "  gzweb dist:  $DIST"
echo "  offline ESM: $DIST/gzweb.bundle.mjs ($(du -h "$DIST/gzweb.bundle.mjs" | awk '{print $1}'))"
