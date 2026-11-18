# Release pipeline secrets

`.github/workflows/release.yml` requires the following GitHub Actions secrets
and variables on `BadryansahBangsawan/Sift`. All must be set before the next tag
push or the notarize/staple steps will fail and ship a broken signature (the
cause of #86). Step-by-step instructions for the repo owner live in
[`RELEASING.md`](../RELEASING.md).

The pipeline uses an **App Store Connect API key** for notarization (modern,
no rotation, scoped to one team) instead of the legacy
`APPLE_ID + app-specific-password` flow.

## Required repository variables (2)

| Variable | Source | Example |
|----------|--------|---------|
| `SIFT_TEAM_ID` | Apple Developer team ID (Membership details) | `ABCDE12345` |
| `SIFT_SIGN_ID` | Full `Developer ID Application` identity string | `Developer ID Application: Your Name (ABCDE12345)` |

The same two values are read from `SIFT_TEAM_ID` and `SIFT_SIGN_ID` by
`scripts/release-local.sh` and `scripts/release-cli-local.sh`.

## Required secrets (7)

| Secret | Source | Notes |
|--------|--------|-------|
| `BUILD_CERTIFICATE_BASE64` | Filtered Developer ID Application `.p12` (cert + matching private key only), base64 | `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password set when exporting the `.p12` | Random — only you and CI need it |
| `KEYCHAIN_PASSWORD` | Random string | Only used to lock the runner's temp keychain — never leaves CI |
| `APP_STORE_CONNECT_KEY_ID` | The 10-char ID from the `.p8` filename (`AuthKey_XXXXXXXXXX.p8`) | e.g. `XXXXXXXXXX` |
| `APP_STORE_CONNECT_ISSUER_ID` | UUID from <https://appstoreconnect.apple.com/access/integrations/api> | e.g. `00000000-0000-0000-0000-000000000000` |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Full contents of the `.p8` file (`-----BEGIN PRIVATE KEY-----` ... `-----END PRIVATE KEY-----`) | Paste raw, including the BEGIN/END lines |

## Homebrew tap access

| Secret | Source | Notes |
|--------|--------|-------|
| `HOMEBREW_TAP_DEPLOY_KEY` | SSH private key for a write-enabled deploy key on `BadryansahBangsawan/homebrew-tap` | Required by release preflight and the external tap update. The in-repo cask uses `GITHUB_TOKEN`. |

The official `Homebrew/homebrew-cask` entry is updated separately through a cask bump pull request after the release is published.

## Extracting your Developer ID cert as a filtered `.p12`

Replace `Your Name (ABCDE12345)` with your own identity before running this;
`security find-identity -v -p codesigning` lists the exact strings.

```bash
mkdir -p ~/Desktop/Sift-secrets && cd ~/Desktop/Sift-secrets

# 1. Export everything from login keychain
P12_PWD=$(openssl rand -base64 24)
echo "$P12_PWD" > P12_PASSWORD.txt
security export -k login.keychain-db -t identities -f pkcs12 -P "$P12_PWD" -o all.p12

# 2. Dump to PEM, isolate the Developer ID cert + matching private key
openssl pkcs12 -in all.p12 -passin "pass:$P12_PWD" -nodes -out all.pem
security find-certificate -c "Developer ID Application: Your Name (ABCDE12345)" -p login.keychain-db > devid.crt

# 3. Use python to split private keys, then match by modulus
python3 - <<'PY'
import re
content = open("all.pem").read()
for i, k in enumerate(re.findall(r"-----BEGIN PRIVATE KEY-----.*?-----END PRIVATE KEY-----", content, re.DOTALL), 1):
    open(f"key_{i}.pem", "w").write(k + "\n")
PY

CERT_MOD=$(openssl x509 -in devid.crt -modulus -noout | shasum -a 256 | awk '{print $1}')
for k in key_*.pem; do
  if [[ "$(openssl rsa -in "$k" -modulus -noout 2>/dev/null | shasum -a 256 | awk '{print $1}')" == "$CERT_MOD" ]]; then
    cp "$k" devid.key && break
  fi
done

# 4. Re-pack as a clean p12 with ONLY Developer ID + key
openssl pkcs12 -export \
  -in devid.crt -inkey devid.key \
  -name "Developer ID Application: Your Name (ABCDE12345)" \
  -out Sift-DeveloperID.p12 \
  -passout "pass:$P12_PWD" \
  -macalg sha256 -keypbe AES-256-CBC -certpbe AES-256-CBC

# 5. Base64 for the GH secret + scrub intermediates
base64 -i Sift-DeveloperID.p12 -o Sift-DeveloperID.p12.b64
rm -P all.p12 all.pem devid.key key_*.pem
```

## Storing the ASC API key locally for `notarytool`

`scripts/release-local.sh` and `scripts/release-cli-local.sh` notarize through a
local `notarytool` keychain profile instead of secrets. Create one for your own
key:

```bash
xcrun notarytool store-credentials AC_NOTARY \
  --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

The profile name is the second argument to both scripts (default `AC_NOTARY`).
The CI workflow uses raw secrets instead (no keychain dependency on the runner).

## Setting them all via gh CLI

```bash
# Fill in the values you control:
P12_PWD=$(cat ~/Desktop/Sift-secrets/P12_PASSWORD.txt)
KC_PWD=$(cat ~/Desktop/Sift-secrets/KEYCHAIN_PASSWORD.txt)

gh variable set SIFT_TEAM_ID  --repo BadryansahBangsawan/Sift --body "ABCDE12345"
gh variable set SIFT_SIGN_ID  --repo BadryansahBangsawan/Sift --body "Developer ID Application: Your Name (ABCDE12345)"

gh secret set BUILD_CERTIFICATE_BASE64       --repo BadryansahBangsawan/Sift < ~/Desktop/Sift-secrets/Sift-DeveloperID.p12.b64
gh secret set P12_PASSWORD                   --repo BadryansahBangsawan/Sift --body "$P12_PWD"
gh secret set KEYCHAIN_PASSWORD              --repo BadryansahBangsawan/Sift --body "$KC_PWD"
gh secret set APP_STORE_CONNECT_KEY_ID       --repo BadryansahBangsawan/Sift --body "XXXXXXXXXX"
gh secret set APP_STORE_CONNECT_ISSUER_ID    --repo BadryansahBangsawan/Sift --body "00000000-0000-0000-0000-000000000000"
gh secret set APP_STORE_CONNECT_PRIVATE_KEY  --repo BadryansahBangsawan/Sift < ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8

# Required tap deploy key:
gh secret set HOMEBREW_TAP_DEPLOY_KEY        --repo BadryansahBangsawan/Sift < /path/to/tap-deploy-key

# Verify:
gh variable list --repo BadryansahBangsawan/Sift
gh secret list --repo BadryansahBangsawan/Sift
```

After upload:

```bash
rm -P ~/Desktop/Sift-secrets/Sift-DeveloperID.p12* \
      ~/Desktop/Sift-secrets/P12_PASSWORD.txt \
      ~/Desktop/Sift-secrets/KEYCHAIN_PASSWORD.txt
```

## Triggering a release

Dry run first (build + sign + notarize, no upload, no homebrew bump):

```bash
gh workflow run release.yml --repo BadryansahBangsawan/Sift -f version=4.0.0 -f dry_run=true
gh run watch --repo BadryansahBangsawan/Sift
```

Real release (after dry run is green):

```bash
git tag v4.0.0
git push origin v4.0.0
```

## What ships

| Artifact | Purpose |
|----------|---------|
| `Sift-X.Y.Z.dmg` | Direct download link in release notes (signed + notarized + stapled) |
| `Sift-X.Y.Z.zip` | Source for the homebrew cask (notarized + stapled `.app` inside) |

Both checksums land in `build/CHECKSUMS.md` and the GH release body.

## Troubleshooting #86 (`code or signature have been modified`)

Root causes that the pipeline guards against, that the previous manual
release path did not:

- Files modified after `codesign` (e.g. running `xcodegen` post-sign breaks the
  signature). The pipeline runs `xcodegen` before `archive` and never edits the
  bundle after the export step.
- Notarizing the `.app` but shipping a `.zip` made before the staple. The
  pipeline staples the `.app` first, then re-zips it. Order matters — Gatekeeper
  on first launch checks the stapled ticket on the `.app`, not the zip.
- Using `Apple Development` cert for distribution — the pipeline overrides with
  `Developer ID Application` at archive time.
- Skipping `--options=runtime` (no hardened runtime → notary rejects). Pipeline
  passes it via `OTHER_CODE_SIGN_FLAGS`.
- Universal-binary signing race where `lipo` is run after sign. The archive
  step builds universal in one pass via `ARCHS="arm64 x86_64"` so the codesign
  covers both slices atomically.
