# Releasing Sift

How the repo owner ships **Sift 4.0.0**. The pipeline builds a universal,
Developer ID-signed app, notarizes it with Apple, staples the ticket, publishes
`Sift-4.0.0.dmg` and `Sift-4.0.0.zip` on GitHub, and bumps both Homebrew casks.

Everything below assumes you own the Apple Developer Team, the GitHub repository
`BadryansahBangsawan/Sift`, and write access to `gh` for that repo. The secrets
reference lives in [`scripts/SECRETS.md`](scripts/SECRETS.md).


## Without a Developer ID: unsigned release

Until the signing secrets below exist, publish with **Actions > Release (unsigned) > Run workflow** (`.github/workflows/release-unsigned.yml`) and enter the version from `project.yml`. It runs the tests, builds a universal app, ad-hoc signs it, packages `Sift-<version>.dmg` and `.zip`, and creates the `v<version>` release with first-launch instructions. It does not notarize and does not touch Homebrew. Users must click **Open Anyway** in System Settings > Privacy & Security once. Switch to the signed workflow below as soon as you can.

## 0. What the release needs

| Item | Where it is used |
|------|------------------|
| Apple Developer Program membership (paid) | Developer ID certificate, notarization |
| Developer ID Application certificate + private key | `.github/workflows/release.yml`, `scripts/release-local.sh` |
| App Store Connect API key | `notarytool` |
| `HOMEBREW_TAP_DEPLOY_KEY` | workflow bumps the tap |
| `BadryansahBangsawan/homebrew-tap` repo | `brew install --cask BadryansahBangsawan/tap/sift` |

Versions in this branch: app `4.1.0` (`project.yml`, build `35`), CLI `1.2.0`
(`cli/Sources/sift/SiftCLI.swift`). The workflow refuses to run when
`MARKETING_VERSION` does not match the tag.

## 1. Get a Developer ID Application certificate

1. In Xcode > Settings > Accounts, add your Apple ID and select the team.
2. Create a certificate signing request: Keychain Access > Certificate
   Assistant > Request a Certificate From a Certificate Authority (saved to
   disk, 2048-bit RSA).
3. Go to <https://developer.apple.com/account/resources/certificates/list>,
   click **+**, choose **Developer ID Application**, upload the CSR, and
   download the `.cer`.
4. Import the `.cer` into the login keychain. Confirm the identity is visible:

   ```bash
   security find-identity -v -p codesigning
   # "Developer ID Application: Your Name (ABCDE12345)"
   ```

5. Copy the **team ID** from <https://developer.apple.com/account> (Membership
   details) and keep the full identity string above; both go into GitHub below.
6. Export a filtered `.p12` containing only this certificate and its key with
   the script in [`scripts/SECRETS.md`](scripts/SECRETS.md#extracting-your-developer-id-cert-as-a-filtered-p12).

## 2. Create an App Store Connect API key

1. Open <https://appstoreconnect.apple.com/access/integrations/api> (Account >
   Users and Access > Integrations > Team Keys).
2. Generate a key with the **Developer** role. Download the `.p8` immediately;
   it can only be downloaded once.
3. Note the **Key ID** (10 characters, also in the filename
   `AuthKey_XXXXXXXXXX.p8`) and the **Issuer ID** (UUID at the top of the page).
4. For local runs, store a notarytool profile:

   ```bash
   xcrun notarytool store-credentials AC_NOTARY \
     --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
     --key-id XXXXXXXXXX \
     --issuer 00000000-0000-0000-0000-000000000000
   ```

## 3. Set the GitHub variables and secrets

The workflow reads two **repository variables** and seven **secrets** on
`BadryansahBangsawan/Sift`:

| Kind | Name | Value |
|------|------|-------|
| Variable | `SIFT_TEAM_ID` | Apple Developer team ID, e.g. `ABCDE12345` |
| Variable | `SIFT_SIGN_ID` | `Developer ID Application: Your Name (ABCDE12345)` |
| Secret | `BUILD_CERTIFICATE_BASE64` | base64 of the filtered `.p12` |
| Secret | `P12_PASSWORD` | `.p12` export password |
| Secret | `KEYCHAIN_PASSWORD` | any random string |
| Secret | `APP_STORE_CONNECT_KEY_ID` | API key ID |
| Secret | `APP_STORE_CONNECT_ISSUER_ID` | API issuer UUID |
| Secret | `APP_STORE_CONNECT_PRIVATE_KEY` | full `.p8` contents |
| Secret | `HOMEBREW_TAP_DEPLOY_KEY` | private deploy key with write access to the tap |

```bash
gh variable set SIFT_TEAM_ID --repo BadryansahBangsawan/Sift --body "ABCDE12345"
gh variable set SIFT_SIGN_ID --repo BadryansahBangsawan/Sift --body "Developer ID Application: Your Name (ABCDE12345)"
gh secret set BUILD_CERTIFICATE_BASE64 --repo BadryansahBangsawan/Sift < Sift-DeveloperID.p12.b64
gh secret set P12_PASSWORD --repo BadryansahBangsawan/Sift --body "$P12_PWD"
gh secret set KEYCHAIN_PASSWORD --repo BadryansahBangsawan/Sift --body "$(openssl rand -base64 24)"
gh secret set APP_STORE_CONNECT_KEY_ID --repo BadryansahBangsawan/Sift --body "XXXXXXXXXX"
gh secret set APP_STORE_CONNECT_ISSUER_ID --repo BadryansahBangsawan/Sift --body "00000000-0000-0000-0000-000000000000"
gh secret set APP_STORE_CONNECT_PRIVATE_KEY --repo BadryansahBangsawan/Sift < AuthKey_XXXXXXXXXX.p8
gh secret set HOMEBREW_TAP_DEPLOY_KEY --repo BadryansahBangsawan/Sift < tap-deploy-key
```

The workflow fails early with an explicit error when either variable is empty.

## 4. Create the Homebrew tap (and its deploy key)

1. Create a public repository `BadryansahBangsawan/homebrew-tap`.
2. Copy [`homebrew/sift.rb`](homebrew/sift.rb) to `Casks/sift.rb` in that repo.
   Leave the version at `4.0.0`; keep `sha256 "SHA256_PLACEHOLDER"`, which the
   release workflow replaces with the checksum of the published zip.
3. Generate a deploy key with write access and add the public half to the tap
   repo under Settings > Deploy keys (allow write access):

   ```bash
   ssh-keygen -t ed25519 -C "sift-release-tap" -f tap-deploy-key -N ""
   # Add tap-deploy-key.pub to https://github.com/BadryansahBangsawan/homebrew-tap/settings/keys
   ```

4. Upload the private half as `HOMEBREW_TAP_DEPLOY_KEY` (step 3).

**Skipping the tap:** the real-release job refuses to publish without
`HOMEBREW_TAP_DEPLOY_KEY`, so you cannot tag a release before the tap exists.
If you do not want a tap yet, use the `workflow_dispatch` dry run (build, sign,
notarize, no upload) and `scripts/release-local.sh` for local artifacts. The
in-repo cask `homebrew/sift.rb` is still bumped by the workflow.

## 5. Cut the release

Dry run first. It builds, signs and notarizes without touching releases or
Homebrew:

```bash
gh workflow run release.yml --repo BadryansahBangsawan/Sift \
  -f version=4.0.0 -f dry_run=true
gh run watch --repo BadryansahBangsawan/Sift
```

When the dry run is green, tag the exact commit that is on `main`:

```bash
git checkout main
git pull
git tag v4.0.0
git push origin v4.0.0
```

The tag push is the canonical release trigger; `workflow_dispatch` without
`dry_run` is rejected by design. Do not run `xcodegen` after the archive step —
the workflow regenerates the project itself before building.

If Apple's notary service is slow, the job waits up to 30 minutes. Re-running a
failed job is safe: an existing draft release is repaired and its assets are
re-verified before republication.

## 6. Verify the published release

1. Confirm the assets and checksums: the release body lists both SHA-256 values;
   compare them with the job log `build/CHECKSUMS.md`.
2. Download and assess the DMG:

   ```bash
   curl -LO https://github.com/BadryansahBangsawan/Sift/releases/download/v4.0.0/Sift-4.0.0.dmg
   spctl -a -vv Sift-4.0.0.dmg          # accepted, source=Notarized Developer ID
   xcrun stapler validate Sift-4.0.0.dmg
   hdiutil attach Sift-4.0.0.dmg
   spctl -a -vv /Volumes/Sift\ 4.0.0/Sift.app
   ```

3. Install, then launch **from `/Applications`**, and check the migration:
   - Preferences from `com.puremac.app` are present (appearance, schedule,
     exclusions).
   - `~/Library/Application Support/Sift` exists and cleanup history is shown on
     the dashboard.
   - Full Disk Access prompts for Sift in onboarding; the old PureMac entry is
     untouched and can be removed.
4. Check for updates in Settings > Updates: it must look at
   `BadryansahBangsawan/Sift` and ignore the old repository.
5. `brew install --cask BadryansahBangsawan/tap/sift` installs `4.0.0` with the
   published zip checksum.

## 7. CLI 1.2.0 (manual, no workflow)

The CLI has no tag-triggered workflow. Build the artifacts locally and publish
them by hand:

```bash
SIFT_TEAM_ID=ABCDE12345 \
SIFT_SIGN_ID="Developer ID Application: Your Name (ABCDE12345)" \
  scripts/release-cli-local.sh 1.2.0 AC_NOTARY
```

The script prints the archive path and notarization ID under
`_work/cli-release/1.2.0/<sha>/`. Create the `cli-v1.2.0` tag on the same
commit, attach `sift-cli-1.2.0.tar.gz` to a GitHub release, and replace the
`sha256` in [`homebrew/sift-cli.rb`](homebrew/sift-cli.rb) with the checksum the
script prints (the file carries a TODO until then). The CLI cannot staple a
ticket; Apple's notarization result ships alongside the archive.

## Rollback

- Delete the GitHub release and move the tag back to the previous release:
  `git tag -f v4.0.0 <old-sha> && git push --force origin v4.0.0` only if that
  release is known-broken; otherwise ship `4.1.0`.
- The Homebrew casks can be reverted with a normal commit to `main` and the tap.
