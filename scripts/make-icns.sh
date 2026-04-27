#!/usr/bin/env bash
# WriteAssist — generates AppIcon.iconset and assets/AppIcon.icns from
# the transparent installer logo PNGs. Run whenever the source artwork changes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${REPO_ROOT}/assets"
ICONSET_DIR="${REPO_ROOT}/AppIcon.iconset"
OUT_ICNS="${REPO_ROOT}/assets/AppIcon.icns"

SRC_128="${SRC_DIR}/write-assist-logo-installer-transparent-128.png"
SRC_256="${SRC_DIR}/write-assist-logo-installer-transparent-256.png"
SRC_512="${SRC_DIR}/write-assist-logo-installer-transparent-512.png"
SRC_1024="${SRC_DIR}/write-assist-logo-installer-transparent-1024.png"

for f in "${SRC_128}" "${SRC_256}" "${SRC_512}" "${SRC_1024}"; do
    if [ ! -f "${f}" ]; then
        echo "Missing source PNG: ${f}" >&2
        exit 1
    fi
done

echo "==> Resetting ${ICONSET_DIR}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# Downscale the smallest source (128) for 16/32/64 slots; copy the rest verbatim.
sips -Z 16 "${SRC_128}" --out "${ICONSET_DIR}/icon_16x16.png"     >/dev/null
sips -Z 32 "${SRC_128}" --out "${ICONSET_DIR}/icon_16x16@2x.png"  >/dev/null
sips -Z 32 "${SRC_128}" --out "${ICONSET_DIR}/icon_32x32.png"     >/dev/null
sips -Z 64 "${SRC_128}" --out "${ICONSET_DIR}/icon_32x32@2x.png"  >/dev/null
cp "${SRC_128}"  "${ICONSET_DIR}/icon_128x128.png"
cp "${SRC_256}"  "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${SRC_256}"  "${ICONSET_DIR}/icon_256x256.png"
cp "${SRC_512}"  "${ICONSET_DIR}/icon_256x256@2x.png"
cp "${SRC_512}"  "${ICONSET_DIR}/icon_512x512.png"
cp "${SRC_1024}" "${ICONSET_DIR}/icon_512x512@2x.png"

echo "==> Compiling ${OUT_ICNS}"
iconutil --convert icns "${ICONSET_DIR}" --output "${OUT_ICNS}"

echo "Done: ${OUT_ICNS}"
