#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PNG="${1:-${ROOT_DIR}/Resources/logo.png}"
OUTPUT_DIR="${2:-${ROOT_DIR}/build/icons}"
ICON_NAME="${3:-AppIcon}"

ICONSET_DIR="${OUTPUT_DIR}/${ICON_NAME}.iconset"
ICNS_PATH="${OUTPUT_DIR}/${ICON_NAME}.icns"
BUNDLED_ICNS_PATH="${ROOT_DIR}/Sources/GuardianHQ/Resources/${ICON_NAME}.icns"

if [[ ! -f "${INPUT_PNG}" ]]; then
  echo "Error: input image not found: ${INPUT_PNG}"
  echo "Usage: scripts/make_app_icon.sh [input_png] [output_dir] [icon_name]"
  exit 1
fi

if [[ "${INPUT_PNG##*.}" != "png" ]]; then
  echo "Error: input must be a PNG file."
  exit 1
fi

dimensions="$(sips -g pixelWidth -g pixelHeight "${INPUT_PNG}" 2>/dev/null)"
width="$(printf "%s\n" "${dimensions}" | awk '/pixelWidth:/{print $2}')"
height="$(printf "%s\n" "${dimensions}" | awk '/pixelHeight:/{print $2}')"

if [[ "${width}" != "${height}" ]]; then
  echo "Error: input image must be square. Found ${width}x${height}."
  exit 1
fi

if [[ "${width}" -lt 1024 ]]; then
  echo "Error: input image must be at least 1024x1024. Found ${width}x${height}."
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
rm -rf "${ICONSET_DIR}" "${ICNS_PATH}"
mkdir -p "${ICONSET_DIR}"

make_png() {
  local size="$1"
  local name="$2"
  sips -z "${size}" "${size}" "${INPUT_PNG}" --out "${ICONSET_DIR}/${name}" >/dev/null
}

make_png 16 icon_16x16.png
make_png 32 icon_16x16@2x.png
make_png 32 icon_32x32.png
make_png 64 icon_32x32@2x.png
make_png 128 icon_128x128.png
make_png 256 icon_128x128@2x.png
make_png 256 icon_256x256.png
make_png 512 icon_256x256@2x.png
make_png 512 icon_512x512.png
make_png 1024 icon_512x512@2x.png

cat > "${ICONSET_DIR}/Contents.json" <<EOF
{
  "images": [
    { "idiom": "mac", "size": "16x16", "scale": "1x", "filename": "icon_16x16.png" },
    { "idiom": "mac", "size": "16x16", "scale": "2x", "filename": "icon_16x16@2x.png" },
    { "idiom": "mac", "size": "32x32", "scale": "1x", "filename": "icon_32x32.png" },
    { "idiom": "mac", "size": "32x32", "scale": "2x", "filename": "icon_32x32@2x.png" },
    { "idiom": "mac", "size": "128x128", "scale": "1x", "filename": "icon_128x128.png" },
    { "idiom": "mac", "size": "128x128", "scale": "2x", "filename": "icon_128x128@2x.png" },
    { "idiom": "mac", "size": "256x256", "scale": "1x", "filename": "icon_256x256.png" },
    { "idiom": "mac", "size": "256x256", "scale": "2x", "filename": "icon_256x256@2x.png" },
    { "idiom": "mac", "size": "512x512", "scale": "1x", "filename": "icon_512x512.png" },
    { "idiom": "mac", "size": "512x512", "scale": "2x", "filename": "icon_512x512@2x.png" }
  ],
  "info": { "version": 1, "author": "xcode" }
}
EOF

iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
mkdir -p "$(dirname "${BUNDLED_ICNS_PATH}")"
cp "${ICNS_PATH}" "${BUNDLED_ICNS_PATH}"

echo "Created iconset: ${ICONSET_DIR}"
echo "Created icns: ${ICNS_PATH}"
echo "Bundled icns copy: ${BUNDLED_ICNS_PATH}"
