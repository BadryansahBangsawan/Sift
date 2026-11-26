#!/bin/bash
# Build one Sparkle appcast item for a Sift release.
#
#   scripts/make-appcast.sh <zip> <version> <build> <release-url> <download-url> <sign_update>
#
# The archive is signed with the Ed25519 private key in
# SPARKLE_ED_PRIVATE_KEY (base64, as exported by `generate_keys -x`). The key
# is never printed and never written to disk: `sign_update --ed-key-file -`
# reads it from standard input.
#
# Options:
#   --output <path>                 where to write appcast.xml (default: appcast.xml)
#   --minimum-system-version <v>    sparkle:minimumSystemVersion (default: 13.0)
#   --verify-public-key <base64>    verify the signature against this key, e.g.
#                                   the app's SUPublicEDKey
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: make-appcast.sh [options] <zip> <version> <build> <release-url> <download-url> <sign_update>

  <zip>            update archive (Sift-<version>.zip)
  <version>        marketing version, e.g. 4.2.0
  <build>          CFBundleVersion, e.g. 40
  <release-url>    GitHub release page for the notes
  <download-url>   URL of the zip asset
  <sign_update>    path to Sparkle 2's sign_update

Options:
  --output <path>                output file (default: appcast.xml)
  --minimum-system-version <v>   default: 13.0
  --verify-public-key <base64>   fail unless the signature verifies against this key

Environment:
  SPARKLE_ED_PRIVATE_KEY   base64 Ed25519 private key (required)
EOF
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

die() {
  printf 'make-appcast: %s\n' "$1" >&2
  exit 1
}

# Verify an Ed25519 signature with CryptoKit; exporting the private seed is not
# needed, so the script can check the app's public key without OpenSSL (the
# macOS system LibreSSL has no Ed25519 support).
verify_signature() {
  local archive="$1" signature="$2" public_key="$3"
  local helper_dir
  helper_dir="$(mktemp -d "${TMPDIR:-/tmp}/sift-verify.XXXXXX")"
  cat > "${helper_dir}/verify.swift" <<'SWIFT'
import CryptoKit
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3,
      let payload = FileManager.default.contents(atPath: args[0]),
      let signature = Data(base64Encoded: args[1]),
      let keyData = Data(base64Encoded: args[2]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else {
    FileHandle.standardError.write(Data("invalid public key or signature encoding\n".utf8))
    exit(2)
}
exit(key.isValidSignature(signature, for: payload) ? 0 : 1)
SWIFT
  local status=0
  swift "${helper_dir}/verify.swift" "$archive" "$signature" "$public_key" || status=$?
  rm -rf "${helper_dir}"
  return "$status"
}

OUTPUT="appcast.xml"
MINIMUM_SYSTEM_VERSION="13.0"
VERIFY_PUBLIC_KEY=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output|-o)
      [[ $# -ge 2 ]] || die "--output needs a path"
      OUTPUT="$2"; shift 2 ;;
    --minimum-system-version)
      [[ $# -ge 2 ]] || die "--minimum-system-version needs a value"
      MINIMUM_SYSTEM_VERSION="$2"; shift 2 ;;
    --verify-public-key)
      [[ $# -ge 2 ]] || die "--verify-public-key needs a base64 key"
      VERIFY_PUBLIC_KEY="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    --*)
      die "unknown option: $1" ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -eq 6 ]] || { usage >&2; exit 2; }
ZIP="${POSITIONAL[0]}"
VERSION="${POSITIONAL[1]}"
BUILD="${POSITIONAL[2]}"
RELEASE_URL="${POSITIONAL[3]}"
DOWNLOAD_URL="${POSITIONAL[4]}"
SIGN_UPDATE="${POSITIONAL[5]}"

[[ -f "$ZIP" ]] || die "no update archive at: $ZIP"
[[ -s "$ZIP" ]] || die "update archive is empty: $ZIP"
[[ -n "$VERSION" ]] || die "marketing version is empty"
[[ -n "$BUILD" ]] || die "build number is empty"
[[ -n "$RELEASE_URL" ]] || die "release page URL is empty"
[[ -n "$DOWNLOAD_URL" ]] || die "download URL is empty"
[[ -x "$SIGN_UPDATE" ]] || die "sign_update is not executable: $SIGN_UPDATE"
[[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]] || die "SPARKLE_ED_PRIVATE_KEY is empty; set the release signing secret"

# Never echo the key. sign_update reads it from stdin with --ed-key-file -.
SIGNATURE="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")" \
  || die "sign_update could not sign $ZIP"
SIGNATURE="${SIGNATURE//[[:space:]]/}"
[[ -n "$SIGNATURE" ]] || die "sign_update returned an empty signature"

LENGTH="$(stat -f%z "$ZIP")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Sift</title>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version $(xml_escape "$VERSION")</title>
      <link>$(xml_escape "$RELEASE_URL")</link>
      <sparkle:releaseNotesLink>$(xml_escape "$RELEASE_URL")</sparkle:releaseNotesLink>
      <sparkle:version>$(xml_escape "$BUILD")</sparkle:version>
      <sparkle:shortVersionString>$(xml_escape "$VERSION")</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(xml_escape "$MINIMUM_SYSTEM_VERSION")</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure url="$(xml_escape "$DOWNLOAD_URL")" length="${LENGTH}" type="application/octet-stream" sparkle:edSignature="${SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF

if [[ -n "$VERIFY_PUBLIC_KEY" ]]; then
  if ! verify_signature "$ZIP" "$SIGNATURE" "$VERIFY_PUBLIC_KEY"; then
    rm -f "$OUTPUT"
    die "the signature does not verify against the supplied public key (SUPublicEDKey / SPARKLE_ED_PRIVATE_KEY mismatch)"
  fi
fi

printf 'Wrote %s (Sift %s, build %s, %s bytes)\n' "$OUTPUT" "$VERSION" "$BUILD" "$LENGTH"