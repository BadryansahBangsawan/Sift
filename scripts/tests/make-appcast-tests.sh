#!/bin/bash
# Tests for scripts/make-appcast.sh. No network and no Keychain access.
#
# Sparkle's sign_update is an external tool the script is given, so point
# SIGN_UPDATE at a copy (for example the Sparkle 2.10.1 release's
# bin/sign_update). The Ed25519 key pairs are throwaway seeds in a temp dir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/make-appcast.sh"
SIGN_UPDATE="${SIGN_UPDATE:-}"

if [[ -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "Set SIGN_UPDATE to Sparkle's bin/sign_update (executable)." >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sift-appcast-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
assert_contains() {
  local file="$1" needle="$2" label="$3"
  grep -Fq -- "$needle" "$file" || fail "$label: '$needle' not found in $file"
}
assert_not_contains() {
  local file="$1" needle="$2" label="$3"
  if grep -Fq -- "$needle" "$file"; then
    fail "$label: '$needle' unexpectedly found in $file"
  fi
}

cat > "$TMP/public-key.swift" <<'SWIFT'
import CryptoKit
import Foundation

guard let seed = Data(base64Encoded: CommandLine.arguments[1]),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    FileHandle.standardError.write(Data("bad seed\n".utf8))
    exit(2)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT

make_seed() {
  head -c 32 /dev/urandom | base64 | tr -d '\n'
}

public_key_for() {
  swift "$TMP/public-key.swift" "$1"
}

KEY_A="$(make_seed)"
KEY_B="$(make_seed)"
PUB_A="$(public_key_for "$KEY_A")"
PUB_B="$(public_key_for "$KEY_B")"
[[ "$PUB_A" != "$PUB_B" ]] || fail "throwaway keys must differ"

mkdir -p "$TMP/payload"
printf 'sift update payload\n' > "$TMP/payload/app"
ditto -c -k --sequesterRsrc "$TMP/payload" "$TMP/Sift-4.2.0.zip"
ZIP="$TMP/Sift-4.2.0.zip"
LENGTH="$(stat -f%z "$ZIP")"
RELEASE_URL="https://github.com/BadryansahBangsawan/Sift/releases/tag/v4.2.0"
DOWNLOAD_URL="https://github.com/BadryansahBangsawan/Sift/releases/download/v4.2.0/Sift-4.2.0.zip"

echo "== writes an appcast item"
OUTPUT="$TMP/appcast.xml"
RUN_LOG="$(SPARKLE_ED_PRIVATE_KEY="$KEY_A" "$SCRIPT" \
  "$ZIP" "4.2.0" "40" "$RELEASE_URL" "$DOWNLOAD_URL" "$SIGN_UPDATE" \
  --output "$OUTPUT" --verify-public-key "$PUB_A" 2>&1)" || fail "script failed: $RUN_LOG"
[[ -f "$OUTPUT" ]] || fail "no appcast at $OUTPUT"

assert_contains "$OUTPUT" "<sparkle:version>40</sparkle:version>" "build number"
assert_contains "$OUTPUT" "<sparkle:shortVersionString>4.2.0</sparkle:shortVersionString>" "marketing version"
assert_contains "$OUTPUT" "<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>" "minimum system"
assert_contains "$OUTPUT" "length=\"$LENGTH\"" "archive length"
assert_contains "$OUTPUT" "url=\"$DOWNLOAD_URL\"" "download URL"
assert_contains "$OUTPUT" "<sparkle:releaseNotesLink>$RELEASE_URL</sparkle:releaseNotesLink>" "release notes link"
assert_contains "$OUTPUT" 'sparkle:edSignature="' "EdDSA signature"
SIGNATURE="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' "$OUTPUT")"
[[ -n "$SIGNATURE" ]] || fail "empty EdDSA signature"
assert_not_contains "$OUTPUT" "$KEY_A" "private key leaked into the appcast"
printf '%s\n' "$RUN_LOG" > "$TMP/run.log"
assert_not_contains "$TMP/run.log" "$KEY_A" "private key leaked into output"

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$OUTPUT" || fail "appcast is not well-formed XML"
fi

echo "== a mismatched public key is rejected"
MATCH_LOG="$TMP/mismatch.log"
if SPARKLE_ED_PRIVATE_KEY="$KEY_A" "$SCRIPT" \
  "$ZIP" "4.2.0" "40" "$RELEASE_URL" "$DOWNLOAD_URL" "$SIGN_UPDATE" \
  --output "$TMP/mismatch.xml" --verify-public-key "$PUB_B" >"$MATCH_LOG" 2>&1; then
  fail "signature verified against the wrong public key"
fi
assert_contains "$MATCH_LOG" "does not verify" "mismatch error"
[[ ! -e "$TMP/mismatch.xml" ]] || fail "a failed verification left appcast.xml behind"

echo "== an empty private key is rejected"
if SPARKLE_ED_PRIVATE_KEY="" "$SCRIPT" \
  "$ZIP" "4.2.0" "40" "$RELEASE_URL" "$DOWNLOAD_URL" "$SIGN_UPDATE" \
  --output "$TMP/nokey.xml" >"$TMP/nokey.log" 2>&1; then
  fail "an empty SPARKLE_ED_PRIVATE_KEY was accepted"
fi
assert_contains "$TMP/nokey.log" "SPARKLE_ED_PRIVATE_KEY" "missing key error"

echo "== a missing archive is rejected"
if SPARKLE_ED_PRIVATE_KEY="$KEY_A" "$SCRIPT" \
  "$TMP/missing.zip" "4.2.0" "40" "$RELEASE_URL" "$DOWNLOAD_URL" "$SIGN_UPDATE" \
  --output "$TMP/missing.xml" >"$TMP/missing.log" 2>&1; then
  fail "a missing archive was accepted"
fi
assert_contains "$TMP/missing.log" "no update archive" "missing archive error"

echo "== XML characters in URLs are escaped"
ESCAPED_URL="https://example.com/a?x=1&y=2"
SPARKLE_ED_PRIVATE_KEY="$KEY_A" "$SCRIPT" \
  "$ZIP" "4.2.0" "40" "https://example.com/notes?a=1&b=2" "$ESCAPED_URL" "$SIGN_UPDATE" \
  --output "$TMP/escaped.xml" >/dev/null 2>&1 || fail "escaping run failed"
assert_contains "$TMP/escaped.xml" "a=1&amp;b=2" "release URL escaped"
assert_contains "$TMP/escaped.xml" "x=1&amp;y=2" "download URL escaped"

echo "OK: make-appcast tests passed"