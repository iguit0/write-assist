# CI/CD Pipeline

## Overview

Two GitHub Actions workflows on `macos-15`:

| Workflow | Trigger | Does | Secrets |
|---|---|---|---|
| `ci.yml` | `pull_request` to `main`, `workflow_dispatch` | Lint + test + DMG build (artifact only) | None |
| `release.yml` | `push` to tags matching `v*` | DMG build → GitHub Release | None |

**Current status: BETA pipeline.** No Apple Developer Program membership, so no Developer ID signing and no notarization. Ad-hoc signing is used, which is enough for Apple Silicon to execute the binary. Users must manually allow the app through Gatekeeper on first launch (documented in `RELEASING.md`). The upgrade path to signed+notarized is described in [Future work](#future-work-notarize-when-developer-account-exists).

## Required secrets

**None.** This is the whole point of the BETA pipeline.

## How `release.yml` works

```
tag push (v*)
  └─▶ resolve version + channel from tag
  └─▶ validate VERSION file matches tag base
  └─▶ install create-dmg
  └─▶ build universal .app via scripts/build-app.sh (ad-hoc signed)
  └─▶ package DMG via scripts/make-dmg.sh
  └─▶ create GitHub Release, attach DMG, mark prerelease if -preview.N
```

Channel detection is tag-pattern-based:
- `v1.2.3-preview.1` → `channel=preview`, `prerelease=true`
- `v1.2.3` → `channel=stable`, `prerelease=false`

## Local debugging

Both scripts under `scripts/` run locally — the preferred way to debug without burning CI minutes:

```bash
# End-to-end dry run
./scripts/build-app.sh 0.0.1-dev.1
./scripts/make-dmg.sh 0.0.1-dev.1

# Open build/WriteAssist-0.0.1-dev.1.dmg in Finder, mount, drag to Applications, launch.
```

If you get "create-dmg not found," install it: `brew install create-dmg`.

## Maintenance playbook

### Upgrading the macOS runner

`macos-15` tracks the latest macOS 15 image. When `macos-15` starts giving deprecation warnings:

1. Update both workflow files' `runs-on` to the new label (e.g., `macos-16` when available).
2. Update `Package.swift`'s `platforms` if you're also bumping the deployment target.
3. Update `LSMinimumSystemVersion` in `Info.plist.template` to match.

### When `swift build` suddenly fails in CI but not locally

Usually an Xcode version skew between your local machine and the CI runner. Pin a specific Xcode in CI:

```yaml
- run: sudo xcode-select -s /Applications/Xcode_16.app
```

The runner images have multiple Xcodes installed; `ls /Applications | grep Xcode` on a runner shows what's available.

### When create-dmg flakes

`create-dmg` occasionally fails with an AppleScript timeout on the GitHub runner. The fix is usually a retry. If it becomes chronic, swap `make-dmg.sh` for a pure-`hdiutil` implementation:

```bash
hdiutil create -volname "WriteAssist ${VERSION}" \
               -srcfolder "${APP_BUNDLE}" \
               -ov -format UDZO \
               "${DMG_PATH}"
```

Less pretty (no background image, no icon positioning) but bulletproof.

## Future work: notarize when Developer account exists

When you enroll in the Apple Developer Program, upgrade the pipeline as follows. This is an **additive** change — branching, versioning, and bundling don't change.

### One-time setup

1. In Xcode: Settings → Accounts → Manage Certificates → `+` → **Developer ID Application**.
2. Export from Keychain Access as `.p12` with a strong password.
3. Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com).
4. Find your Team ID at `developer.apple.com/account`.
5. Add GitHub secrets (Settings → Secrets and variables → Actions):
   - `MACOS_CERTIFICATE` — `base64 -i cert.p12 | pbcopy`
   - `MACOS_CERTIFICATE_PWD` — the `.p12` password
   - `KEYCHAIN_PASSWORD` — any random string
   - `SIGNING_IDENTITY` — exact string from `security find-identity -v -p codesigning`
   - `APPLE_ID` — your Apple ID email
   - `APPLE_TEAM_ID` — 10-char Team ID
   - `APPLE_APP_SPECIFIC_PASSWORD` — from step 3

### Workflow changes

Add a new `assets/WriteAssist.entitlements` (empty `<dict/>`), and add these steps to `release.yml` between "Build .app" and "Build DMG":

```yaml
      - name: Import Developer ID certificate
        env:
          MACOS_CERTIFICATE: ${{ secrets.MACOS_CERTIFICATE }}
          MACOS_CERTIFICATE_PWD: ${{ secrets.MACOS_CERTIFICATE_PWD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERT_PATH="${RUNNER_TEMP}/cert.p12"
          KEYCHAIN_PATH="${RUNNER_TEMP}/build.keychain"
          echo "${MACOS_CERTIFICATE}" | base64 --decode > "${CERT_PATH}"
          security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
          security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
          security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
          security import "${CERT_PATH}" -P "${MACOS_CERTIFICATE_PWD}" -A -t cert -f pkcs12 -k "${KEYCHAIN_PATH}"
          security set-key-partition-list -S apple-tool:,apple: -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
          security list-keychains -d user -s "${KEYCHAIN_PATH}" $(security list-keychains -d user | tr -d '"')

      - name: Sign .app with Developer ID
        env:
          SIGNING_IDENTITY: ${{ secrets.SIGNING_IDENTITY }}
        run: |
          codesign --force --deep --options runtime \
              --entitlements assets/WriteAssist.entitlements \
              --sign "${SIGNING_IDENTITY}" --timestamp \
              build/WriteAssist.app
          codesign --verify --verbose=4 build/WriteAssist.app
```

And between "Build DMG" and "Publish GitHub Release":

```yaml
      - name: Notarize DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
        run: |
          DMG="build/WriteAssist-${{ steps.meta.outputs.version }}.dmg"
          codesign --force --sign "${{ secrets.SIGNING_IDENTITY }}" --timestamp "${DMG}"
          xcrun notarytool submit "${DMG}" \
              --apple-id "${APPLE_ID}" --team-id "${APPLE_TEAM_ID}" \
              --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
              --wait --timeout 30m
          xcrun stapler staple "${DMG}"
          xcrun stapler validate "${DMG}"
```

Update `scripts/build-app.sh` to replace the ad-hoc sign step with the real identity (falling back to ad-hoc for local dev when `SIGNING_IDENTITY` is unset):

```bash
IDENTITY="${SIGNING_IDENTITY:--}"  # default to ad-hoc
codesign --force --deep --options runtime \
    --entitlements "${REPO_ROOT}/assets/WriteAssist.entitlements" \
    --sign "${IDENTITY}" --timestamp \
    "${APP_BUNDLE}"
```

Once live, delete the "BETA / Preview build" warning block from `release.yml`'s release body, and remove the "Installing a BETA build" section from `RELEASING.md`.

## What the pipeline does NOT do (yet)

- **Auto-update via Sparkle** — testers download manually. Adding Sparkle later is straightforward; it needs an EdDSA key pair and an `appcast.xml`.
- **Symbol upload for crash reporting** — no dSYMs archived. If you add Sentry/Bugsnag, upload dSYMs from the same workflow.
- **Homebrew cask** — if you ever want `brew install --cask writeassist`, that requires notarization first.
