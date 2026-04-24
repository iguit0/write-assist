#!/usr/bin/env bash
# WriteAssist — builds the SPM executable, assembles a .app bundle, ad-hoc signs it.
set -euo pipefail

VERSION="${1:?Usage: build-app.sh <version> [build_number]}"
BUILD_NUMBER="${2:-$(git rev-list --count HEAD)}"

APP_NAME="WriteAssist"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
SPM_BUILD_DIR="${REPO_ROOT}/.build/apple/Products/Release"

echo "==> Cleaning previous build"
rm -rf "${BUILD_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "==> Building universal release binary"
cd "${REPO_ROOT}"
swift build \
    --configuration release \
    --arch arm64 \
    --arch x86_64

echo "==> Assembling .app bundle"
cp "${SPM_BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# SPM-generated resource bundle for WriteAssistCore (JSON rules, etc.)
if [ -d "${SPM_BUILD_DIR}/${APP_NAME}_WriteAssistCore.bundle" ]; then
    cp -R "${SPM_BUILD_DIR}/${APP_NAME}_WriteAssistCore.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

cp "${REPO_ROOT}/assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> Writing Info.plist (version ${VERSION}, build ${BUILD_NUMBER})"
sed -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@BUILD_NUMBER@/${BUILD_NUMBER}/g" \
    "${REPO_ROOT}/assets/Info.plist.template" \
    > "${APP_BUNDLE}/Contents/Info.plist"

echo "==> Ad-hoc signing (required for Apple Silicon)"
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Verifying"
file "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
codesign -dv "${APP_BUNDLE}" 2>&1 | grep -E '(Identifier|Signature)'
defaults read "${APP_BUNDLE}/Contents/Info.plist" CFBundleShortVersionString

echo "Done: ${APP_BUNDLE}"
