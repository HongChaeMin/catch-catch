#!/usr/bin/env bash
# catch-catch macOS release: build → sign → notarize → staple → package → GitHub release
#
# Usage:
#   scripts/release-mac.sh vX.Y.Z "릴리즈 노트"
#
# Prereqs (one-time):
#   1. Developer ID cert in login keychain:
#        "Developer ID Application: Chaemin Hong (BN55DYU669)"
#   2. Notary profile stored in keychain:
#        xcrun notarytool store-credentials "catch-catch-notary" \
#          --apple-id <apple id> --team-id BN55DYU669
set -euo pipefail

VERSION="${1:?usage: release-mac.sh vX.Y.Z [notes]}"
NOTES="${2:-Release $VERSION}"
SHORT_VERSION="${VERSION#v}"

TEAM_ID="BN55DYU669"
SIGN_IDENTITY="Developer ID Application: Chaemin Hong (${TEAM_ID})"
NOTARY_PROFILE="catch-catch-notary"
REPO="HongChaeMin/catch-catch"

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
DERIVED="${PROJECT_ROOT}/.claude/tmp/DerivedData"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_PATH="${BUILD_DIR}/catch-catch.app"
DMG_RW="${BUILD_DIR}/dmg_rw.dmg"
DMG_OUT="${BUILD_DIR}/catch-catch.dmg"
ZIP_OUT="${BUILD_DIR}/catch-catch.zip"

echo "==> [1/9] Bump Info.plist to ${SHORT_VERSION}"
BUILD_NUMBER="${SHORT_VERSION##*.}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" catch-catch/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" catch-catch/Info.plist

echo "==> [2/9] xcodegen"
xcodegen generate

echo "==> [3/9] xcodebuild Release (Developer ID signing)"
rm -rf "${DERIVED}"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme catch-catch -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  -configuration Release \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  ENABLE_HARDENED_RUNTIME=YES \
  build 2>&1 | tail -30

echo "==> [4/9] Copy .app to build/"
rm -rf "${APP_PATH}"
cp -R "${DERIVED}/Build/Products/Release/catch-catch.app" "${APP_PATH}"

echo "==> [5/9] Re-sign Sparkle internals + app (inside-out)"
# xcodebuild only signs the top-level app; Sparkle.framework ships with
# its own internal bundles (Updater.app, Autoupdate, XPC services) that
# must be re-signed with Developer ID + hardened runtime + timestamp.
SPARKLE="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
SPARKLE_VER="${SPARKLE}/Versions/B"
CS_FLAGS=(--force --options runtime --timestamp --sign "${SIGN_IDENTITY}")

codesign "${CS_FLAGS[@]}" "${SPARKLE_VER}/XPCServices/Installer.xpc"
codesign "${CS_FLAGS[@]}" "${SPARKLE_VER}/XPCServices/Downloader.xpc"
codesign "${CS_FLAGS[@]}" "${SPARKLE_VER}/Updater.app"
codesign "${CS_FLAGS[@]}" "${SPARKLE_VER}/Autoupdate"
codesign "${CS_FLAGS[@]}" "${SPARKLE}"

# Re-sign the app with our entitlements (strips get-task-allow that
# Xcode injects for Debug, which Release sometimes still inherits).
codesign "${CS_FLAGS[@]}" \
  --entitlements catch-catch/catch-catch.entitlements \
  "${APP_PATH}"

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign -dvv "${APP_PATH}" 2>&1 | grep -E "Authority|TeamIdentifier|flags"

echo "==> [6/9] Notarize .app (submit zip → wait → staple)"
NOTARY_ZIP="${BUILD_DIR}/catch-catch-notary.zip"
rm -f "${NOTARY_ZIP}"
ditto -c -k --keepParent "${APP_PATH}" "${NOTARY_ZIP}"
xcrun notarytool submit "${NOTARY_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
rm -f "${NOTARY_ZIP}"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

echo "==> [7/9] Build DMG (replace .app inside RW template)"
if [ ! -f "${DMG_RW}" ]; then
  echo "ERROR: ${DMG_RW} not found. RW template required (layout/background baked in)." >&2
  exit 1
fi
# Detach stale mount if any
hdiutil detach "/Volumes/catch-catch" -quiet 2>/dev/null || true
hdiutil attach "${DMG_RW}" -nobrowse
rm -rf "/Volumes/catch-catch/catch-catch.app"
cp -R "${APP_PATH}" "/Volumes/catch-catch/catch-catch.app"
hdiutil detach "/Volumes/catch-catch"
rm -f "${DMG_OUT}"
hdiutil convert "${DMG_RW}" -format UDZO -o "${DMG_OUT}"

echo "==> [8/9] Sign & notarize DMG"
codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_OUT}"
xcrun notarytool submit "${DMG_OUT}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait
xcrun stapler staple "${DMG_OUT}"

# ZIP
rm -f "${ZIP_OUT}"
(cd "${BUILD_DIR}" && zip -rq catch-catch.zip catch-catch.app)

echo "==> [9/9] GitHub Release ${VERSION}"
unset GITHUB_TOKEN
gh release create "${VERSION}" \
  "${DMG_OUT}" "${ZIP_OUT}" \
  --repo "${REPO}" \
  --title "${VERSION}" \
  --notes "${NOTES}"

echo "✅ Released ${VERSION}"
