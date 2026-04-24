#!/usr/bin/env bash
# WriteAssist — packages the .app into a .dmg
set -euo pipefail

VERSION="${1:?Usage: make-dmg.sh <version>}"
APP_BUNDLE="${2:-build/WriteAssist.app}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
DMG_PATH="${BUILD_DIR}/WriteAssist-${VERSION}.dmg"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "create-dmg not found. Install with: brew install create-dmg" >&2
    exit 1
fi

# Clean any half-baked mounts from previous failed runs
hdiutil detach "/Volumes/WriteAssist ${VERSION}" 2>/dev/null || true

echo "==> Creating DMG at ${DMG_PATH}"
create-dmg \
    --volname "WriteAssist ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 380 \
    --icon-size 100 \
    --icon "WriteAssist.app" 170 180 \
    --hide-extension "WriteAssist.app" \
    --app-drop-link 430 180 \
    --no-internet-enable \
    "${DMG_PATH}" \
    "${APP_BUNDLE}"

echo "Done: ${DMG_PATH}"
