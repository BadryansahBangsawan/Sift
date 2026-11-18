#!/usr/bin/env bash
#
# Local mirror of .github/workflows/release.yml for producing and validating
# release artifacts. The tag-triggered CI workflow remains the canonical
# publisher. Requires:
#   - Developer ID Application identity in your login keychain
#   - notarytool keychain profile already stored, e.g.:
#       xcrun notarytool store-credentials AC_NOTARY \
#         --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
#         --key-id XXXXXXXXXX --issuer 00000000-0000-0000-0000-000000000000
#   - xcodegen + create-dmg installed (brew install xcodegen create-dmg)
#
# Signing identity comes from the environment, never from a default:
#   SIFT_TEAM_ID  Apple Developer team ID, 10 characters (ABCDE12345)
#   SIFT_SIGN_ID  Full codesign identity, e.g.
#                 "Developer ID Application: Your Name (ABCDE12345)"
#
# Usage: scripts/release-local.sh <version> [notary_profile]
#        SIFT_TEAM_ID=ABCDE12345 \
#        SIFT_SIGN_ID="Developer ID Application: Your Name (ABCDE12345)" \
#          scripts/release-local.sh 4.0.0
#        scripts/release-local.sh 4.0.0 AC_NOTARY
#
set -euo pipefail

VERSION="${1:?Usage: $0 <version> [notary_profile]}"
NOTARY_PROFILE="${2:-AC_NOTARY}"
: "${SIFT_TEAM_ID:?SIFT_TEAM_ID is not set. Export your Apple Developer team ID (10 characters, e.g. ABCDE12345).}"
: "${SIFT_SIGN_ID:?SIFT_SIGN_ID is not set. Export your signing identity, e.g. \"Developer ID Application: Your Name (ABCDE12345)\".}"
TEAM_ID="${SIFT_TEAM_ID}"
SIGN_ID="${SIFT_SIGN_ID}"
SCHEME="Sift"
PROJECT="Sift.xcodeproj"
APP="build/export/Sift.app"
DMG="build/Sift-${VERSION}.dmg"
ZIP="build/Sift-${VERSION}.zip"

cd "$(dirname "$0")/.."

SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if [[ ! "${VERSION}" =~ ${SEMVER_RE} ]]; then
  echo "ERROR: version must be strict SemVer core (for example, 2.9.8; no leading zeroes): ${VERSION}" >&2
  exit 1
fi

BUILD_SHA=$(git rev-parse 'HEAD^{commit}')
TAG="v${VERSION}"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: tracked release inputs must be committed before building artifacts" >&2
  exit 1
fi
UNTRACKED_INPUTS=$(git ls-files --others --exclude-standard -- Sift project.yml Sift.xcodeproj)
if [[ -n "${UNTRACKED_INPUTS}" ]]; then
  echo "ERROR: untracked release inputs must be committed before building artifacts:" >&2
  printf '%s\n' "${UNTRACKED_INPUTS}" >&2
  exit 1
fi

git fetch --no-tags origin main
REMOTE_MAIN_SHA=$(git rev-parse 'origin/main^{commit}')
if [[ "${BUILD_SHA}" != "${REMOTE_MAIN_SHA}" ]]; then
  echo "ERROR: current commit ${BUILD_SHA} is not the latest origin/main commit ${REMOTE_MAIN_SHA}" >&2
  exit 1
fi

if LOCAL_TAG_SHA=$(git rev-parse "${TAG}^{commit}" 2>/dev/null) && [[ "${LOCAL_TAG_SHA}" != "${BUILD_SHA}" ]]; then
  echo "ERROR: local tag ${TAG} resolves to ${LOCAL_TAG_SHA}, not current commit ${BUILD_SHA}" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  git fetch --force origin "refs/tags/${TAG}:refs/tags/${TAG}"
  TAG_SHA=$(git rev-parse "${TAG}^{commit}")
  if [[ "${TAG_SHA}" != "${BUILD_SHA}" ]]; then
    echo "ERROR: remote tag ${TAG} resolves to ${TAG_SHA}, not current commit ${BUILD_SHA}" >&2
    exit 1
  fi
fi

PROJ_VERSION=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml)
if [[ "${PROJ_VERSION}" != "${VERSION}" ]]; then
  echo "ERROR: project.yml MARKETING_VERSION (${PROJ_VERSION}) != ${VERSION}" >&2
  exit 1
fi

rm -rf build
mkdir -p build

echo "==> xcodegen"
xcodegen generate

echo "==> archive"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Sift.xcarchive \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGN_ID}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  archive

echo "==> export"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath build/Sift.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist

echo "==> verify codesign"
codesign --verify --deep --strict --verbose=2 "${APP}"
codesign -dvv "${APP}" 2>&1 | grep -E "Identifier|TeamIdentifier|flags|Authority"
codesign -dvv "${APP}" 2>&1 | grep -q "flags=0x10000(runtime)" || { echo "Hardened runtime missing"; exit 1; }
APP_ARCHS=$(lipo -archs "${APP}/Contents/MacOS/Sift")
grep -qw arm64 <<< "${APP_ARCHS}" || { echo "arm64 slice missing" >&2; exit 1; }
grep -qw x86_64 <<< "${APP_ARCHS}" || { echo "x86_64 slice missing" >&2; exit 1; }
echo "Architectures: ${APP_ARCHS}"

echo "==> notarize app zip (profile: ${NOTARY_PROFILE})"
NOTARY_ZIP="build/Sift-app-notary.zip"
ditto -c -k --keepParent --sequesterRsrc "${APP}" "${NOTARY_ZIP}"
xcrun notarytool submit "${NOTARY_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait --timeout 30m
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
spctl --assess --type execute --verbose=4 "${APP}"
rm -f "${NOTARY_ZIP}"

echo "==> dmg from stapled app"
create-dmg \
  --volname "Sift ${VERSION}" \
  --window-size 540 360 \
  --icon-size 100 \
  --icon "Sift.app" 140 180 \
  --hide-extension "Sift.app" \
  --app-drop-link 400 180 \
  --no-internet-enable \
  "${DMG}" \
  build/export/Sift.app
codesign --sign "${SIGN_ID}" --timestamp "${DMG}"
codesign --verify --verbose=2 "${DMG}"

echo "==> notarize dmg"
xcrun notarytool submit "${DMG}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait --timeout 30m
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"
spctl --assess --type install --verbose=4 "${DMG}"

echo "==> final zip with stapled app"
ditto -c -k --keepParent --sequesterRsrc "${APP}" "${ZIP}"

DMG_SHA=$(shasum -a 256 "${DMG}" | awk '{print $1}')
ZIP_SHA=$(shasum -a 256 "${ZIP}" | awk '{print $1}')

echo ""
echo "===================="
echo "Sift ${VERSION} signed + notarized"
echo "===================="
echo "DMG: ${DMG}"
echo "  sha256: ${DMG_SHA}"
echo "ZIP: ${ZIP}"
echo "  sha256: ${ZIP_SHA}"
echo ""
echo "Canonical publish: push ${TAG} at commit ${BUILD_SHA}; the tag-triggered CI workflow uploads assets and updates both Homebrew casks."
echo "This local script does not create tags, publish a GitHub release, or update Homebrew."
